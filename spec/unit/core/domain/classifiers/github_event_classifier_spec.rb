# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::Classifiers::GithubEventClassifier do
  let(:dimension_extractor) { Domain::Extractors::DimensionExtractor.new }
  let(:classifier) { described_class.new(dimension_extractor) }

  describe "#classify" do
    context "with a push event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "github.push",
          source: "github",
          data: {
            repository: { full_name: "example/repo" },
            commits: [
              {
                id: "abc123",
                message: "feat(users): add login functionality",
                added: ["src/users/login.rb", "src/users/logout.rb"],
                modified: ["src/app.rb"],
                removed: [],
                stats: { additions: 100, deletions: 20 }
              },
              {
                id: "def456",
                message: "fix(api)!: breaking change in API response format",
                added: [],
                modified: ["api/response.rb", "api/format.rb"],
                removed: ["api/old_format.rb"],
                stats: { additions: 50, deletions: 30 }
              }
            ],
            ref: "refs/heads/main",
            sender: { login: "octocat" }
          }
        )
      end

      it "returns the expected basic metrics" do
        result = classifier.classify(event)

        expect(result).to be_a(Hash)
        expect(result[:metrics]).to be_an(Array)

        # We no longer check for exact size since we have many new metrics
        expect(result[:metrics].size).to be > 4

        # Check for push.total metric
        total_metric = result[:metrics].find { |m| m[:name] == "github.push.total" }
        expect(total_metric).to be_present
        expect(total_metric[:value]).to eq(1)
        expect(total_metric[:dimensions][:repository]).to eq("example/repo")
        expect(total_metric[:dimensions][:organization]).to eq("example")

        # Check for push.commits metric
        commits_metric = result[:metrics].find { |m| m[:name] == "github.push.commits" }
        expect(commits_metric).to be_present
        expect(commits_metric[:value]).to eq(2) # Two commits in data

        # Check for branch activity metric
        branch_metric = result[:metrics].find { |m| m[:name] == "github.push.branch_activity" }
        expect(branch_metric).to be_present
        expect(branch_metric[:dimensions][:branch]).to eq("main")

        # Check for author metric
        author_metric = result[:metrics].find { |m| m[:name] == "github.push.by_author" }
        expect(author_metric).to be_present
        expect(author_metric[:dimensions][:author]).to eq("octocat")
      end

      it "tracks conventional commit metrics" do
        result = classifier.classify(event)

        # Check for commit type metrics
        commit_type_metrics = result[:metrics].select { |m| m[:name] == "github.push.commit_type" }
        expect(commit_type_metrics.size).to eq(2) # Two conventional commits

        # Check feature commit
        feat_metric = commit_type_metrics.find { |m| m[:dimensions][:type] == "feat" }
        expect(feat_metric).to be_present
        expect(feat_metric[:dimensions][:scope]).to eq("users")

        # Check fix commit
        fix_metric = commit_type_metrics.find { |m| m[:dimensions][:type] == "fix" }
        expect(fix_metric).to be_present
        expect(fix_metric[:dimensions][:scope]).to eq("api")

        # Check breaking change metrics
        breaking_metrics = result[:metrics].select { |m| m[:name] == "github.push.breaking_change" }
        expect(breaking_metrics.size).to eq(1) # One breaking change
        expect(breaking_metrics.first[:dimensions][:type]).to eq("fix")
        expect(breaking_metrics.first[:dimensions][:scope]).to eq("api")
      end

      it "tracks file change metrics" do
        result = classifier.classify(event)

        # Check file count metrics
        files_added_metric = result[:metrics].find { |m| m[:name] == "github.push.files_added" }
        expect(files_added_metric).to be_present
        expect(files_added_metric[:value]).to eq(2) # Two files added

        files_modified_metric = result[:metrics].find { |m| m[:name] == "github.push.files_modified" }
        expect(files_modified_metric).to be_present
        expect(files_modified_metric[:value]).to eq(3) # Three files modified

        files_removed_metric = result[:metrics].find { |m| m[:name] == "github.push.files_removed" }
        expect(files_removed_metric).to be_present
        expect(files_removed_metric[:value]).to eq(1) # One file removed
      end

      it "tracks directory hotspot metrics" do
        result = classifier.classify(event)

        # Check directory hotspot metrics
        dir_hotspot_metric = result[:metrics].find { |m| m[:name] == "github.push.directory_hotspot" }
        expect(dir_hotspot_metric).to be_present

        # Check individual directory metrics
        dir_metrics = result[:metrics].select { |m| m[:name] == "github.push.directory_changes" }
        expect(dir_metrics.size).to be > 0

        # We should have metrics for "src/users", "src", "api" directories
        src_users_metric = dir_metrics.find { |m| m[:dimensions][:directory] == "src/users" }
        expect(src_users_metric).to be_present
        expect(src_users_metric[:value]).to eq(2) # Two files in src/users

        api_metric = dir_metrics.find { |m| m[:dimensions][:directory] == "api" }
        expect(api_metric).to be_present
        expect(api_metric[:value]).to eq(3) # Three files in api
      end

      it "tracks file extension metrics" do
        result = classifier.classify(event)

        # Check file extension hotspot metric
        ext_hotspot_metric = result[:metrics].find { |m| m[:name] == "github.push.filetype_hotspot" }
        expect(ext_hotspot_metric).to be_present

        # Check individual extension metrics
        ext_metrics = result[:metrics].select { |m| m[:name] == "github.push.filetype_changes" }
        expect(ext_metrics.size).to be > 0

        # All files are .rb
        rb_metric = ext_metrics.find { |m| m[:dimensions][:filetype] == "rb" }
        expect(rb_metric).to be_present
        expect(rb_metric[:value]).to eq(6) # Six Ruby files
      end

      it "tracks code volume metrics" do
        result = classifier.classify(event)

        # Check code volume metrics
        additions_metric = result[:metrics].find { |m| m[:name] == "github.push.code_additions" }
        expect(additions_metric).to be_present
        expect(additions_metric[:value]).to eq(150) # 100 + 50

        deletions_metric = result[:metrics].find { |m| m[:name] == "github.push.code_deletions" }
        expect(deletions_metric).to be_present
        expect(deletions_metric[:value]).to eq(50) # 20 + 30

        churn_metric = result[:metrics].find { |m| m[:name] == "github.push.code_churn" }
        expect(churn_metric).to be_present
        expect(churn_metric[:value]).to eq(200) # 150 + 50
      end
    end

    context "with a complex push event containing diverse commits" do
      let(:complex_event) do
        FactoryBot.build(
          :event,
          name: "github.push",
          source: "github",
          data: {
            repository: { full_name: "rails/rails" },
            commits: [
              {
                id: "commit1",
                message: "feat(activerecord): add support for PostgreSQL 14 features",
                added: [
                  "activerecord/lib/active_record/connection_adapters/postgresql/features.rb",
                  "activerecord/lib/active_record/connection_adapters/postgresql/schema_statements.rb"
                ],
                modified: [
                  "activerecord/lib/active_record/connection_adapters/postgresql_adapter.rb"
                ],
                removed: [],
                stats: { additions: 120, deletions: 15 }
              },
              {
                id: "commit2",
                message: "fix(actionpack): resolve routing regression with wildcard segments",
                added: [],
                modified: [
                  "actionpack/lib/action_dispatch/routing/route_set.rb",
                  "actionpack/lib/action_dispatch/journey/router.rb"
                ],
                removed: [],
                stats: { additions: 35, deletions: 28 }
              },
              {
                id: "commit3",
                message: "docs: update API documentation for ActionCable",
                added: [],
                modified: [
                  "guides/source/action_cable_overview.md",
                  "actioncable/README.md"
                ],
                removed: [],
                stats: { additions: 65, deletions: 12 }
              },
              {
                id: "commit4",
                message: "refactor(actionview)!: change template rendering pipeline",
                added: [
                  "actionview/lib/action_view/renderer/new_pipeline.rb"
                ],
                modified: [
                  "actionview/lib/action_view/renderer.rb",
                  "actionview/lib/action_view/renderer/renderer.rb",
                  "actionview/lib/action_view/helpers/rendering_helper.rb"
                ],
                removed: [
                  "actionview/lib/action_view/renderer/old_pipeline.rb"
                ],
                stats: { additions: 230, deletions: 185 }
              },
              {
                id: "commit5",
                message: "Fixed the admin authentication issue",
                added: [],
                modified: [
                  "app/controllers/admin_controller.rb",
                  "app/models/admin.rb"
                ],
                removed: [],
                stats: { additions: 45, deletions: 12 }
              }
            ],
            ref: "refs/heads/main",
            sender: { login: "dhh" }
          }
        )
      end

      it "correctly classifies all commit types" do
        result = classifier.classify(complex_event)

        # Check for commit type metrics (including both conventional and inferred)
        commit_type_metrics = result[:metrics].select { |m| m[:name] == "github.push.commit_type" }
        expect(commit_type_metrics.size).to eq(5) # All commits, both conventional and inferred

        # Check feature commit
        feat_metric = commit_type_metrics.find { |m| m[:dimensions][:type] == "feat" }
        expect(feat_metric).to be_present
        expect(feat_metric[:dimensions][:scope]).to eq("activerecord")

        # Check fix commits (both conventional and inferred)
        fix_metrics = commit_type_metrics.select { |m| m[:dimensions][:type] == "fix" }
        expect(fix_metrics.size).to eq(2) # One conventional, one inferred

        # At least one should be conventional
        conventional_fix = fix_metrics.find { |m| m[:dimensions][:conventional] == "true" }
        expect(conventional_fix).to be_present
        expect(conventional_fix[:dimensions][:scope]).to eq("actionpack")

        # And one should be inferred (non-conventional)
        inferred_fix = fix_metrics.find { |m| m[:dimensions][:conventional] == "false" }
        expect(inferred_fix).to be_present
      end

      it "correctly identifies breaking changes" do
        result = classifier.classify(complex_event)

        breaking_metrics = result[:metrics].select { |m| m[:name] == "github.push.breaking_change" }
        expect(breaking_metrics.size).to eq(1)

        breaking_metric = breaking_metrics.first
        expect(breaking_metric[:dimensions][:type]).to eq("refactor")
        expect(breaking_metric[:dimensions][:scope]).to eq("actionview")
        expect(breaking_metric[:dimensions][:author]).to eq("dhh")
      end

      it "correctly tracks directory hotspots" do
        result = classifier.classify(complex_event)

        directory_metrics = result[:metrics].select { |m| m[:name] == "github.push.directory_changes" }

        # Check that main Rails component directories are counted
        actionview_metric = directory_metrics.find { |m| m[:dimensions][:directory] == "actionview" }
        expect(actionview_metric).to be_present
        expect(actionview_metric[:value]).to be >= 4

        actionview_lib_metric = directory_metrics.find { |m| m[:dimensions][:directory] == "actionview/lib" }
        expect(actionview_lib_metric).to be_present

        activerecord_metric = directory_metrics.find { |m| m[:dimensions][:directory] == "activerecord" }
        expect(activerecord_metric).to be_present
        expect(activerecord_metric[:value]).to be >= 3
      end

      it "correctly tracks file extension metrics" do
        result = classifier.classify(complex_event)

        # File extension metrics should be tracked
        ext_metrics = result[:metrics].select { |m| m[:name] == "github.push.filetype_changes" }
        expect(ext_metrics.size).to be > 0

        # Ruby files
        rb_metric = ext_metrics.find { |m| m[:dimensions][:filetype] == "rb" }
        expect(rb_metric).to be_present
        expect(rb_metric[:value]).to eq(12) # Update based on new data

        # Markdown files
        md_metric = ext_metrics.find { |m| m[:dimensions][:filetype] == "md" }
        expect(md_metric).to be_present
        expect(md_metric[:value]).to eq(2)
      end

      it "correctly tracks code volume metrics" do
        result = classifier.classify(complex_event)

        # Code volume metrics
        additions_metric = result[:metrics].find { |m| m[:name] == "github.push.code_additions" }
        expect(additions_metric).to be_present
        expect(additions_metric[:value]).to eq(495) # Sum of all additions

        deletions_metric = result[:metrics].find { |m| m[:name] == "github.push.code_deletions" }
        expect(deletions_metric).to be_present
        expect(deletions_metric[:value]).to eq(252) # Sum of all deletions

        churn_metric = result[:metrics].find { |m| m[:name] == "github.push.code_churn" }
        expect(churn_metric).to be_present
        expect(churn_metric[:value]).to eq(747) # Sum of additions and deletions
      end

      it "provides aggregated repository metrics" do
        result = classifier.classify(complex_event)

        # Basic push metrics should be present
        total_metric = result[:metrics].find { |m| m[:name] == "github.push.total" }
        expect(total_metric).to be_present
        expect(total_metric[:dimensions][:repository]).to eq("rails/rails")

        # Commit count should be correct
        commits_metric = result[:metrics].find { |m| m[:name] == "github.push.commits" }
        expect(commits_metric).to be_present
        expect(commits_metric[:value]).to eq(5) # 5 commits

        # Author should be correctly identified
        author_metric = result[:metrics].find { |m| m[:name] == "github.push.by_author" }
        expect(author_metric).to be_present
        expect(author_metric[:dimensions][:author]).to eq("dhh")
      end
    end

    context "with a pull request event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "github.pull_request.opened",
          source: "github",
          data: {
            repository: { full_name: "example/repo" },
            sender: { login: "octocat" }
          }
        )
      end

      it "returns the expected metrics" do
        result = classifier.classify(event)

        expect(result[:metrics].size).to eq(3)

        # Check for PR total metric
        total_metric = result[:metrics].find { |m| m[:name] == "github.pull_request.total" }
        expect(total_metric).to be_present
        expect(total_metric[:dimensions][:action]).to eq("opened")

        # Check for PR opened metric
        opened_metric = result[:metrics].find { |m| m[:name] == "github.pull_request.opened" }
        expect(opened_metric).to be_present

        # Check for author metric
        author_metric = result[:metrics].find { |m| m[:name] == "github.pull_request.by_author" }
        expect(author_metric).to be_present
        expect(author_metric[:dimensions][:author]).to eq("octocat")
      end
    end

    context "with an issues event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "github.issues.closed",
          source: "github",
          data: {
            repository: { full_name: "example/repo" },
            sender: { login: "octocat" }
          }
        )
      end

      it "returns the expected metrics" do
        result = classifier.classify(event)

        expect(result[:metrics].size).to eq(3)

        # Check for issues total metric
        total_metric = result[:metrics].find { |m| m[:name] == "github.issues.total" }
        expect(total_metric).to be_present
        expect(total_metric[:dimensions][:action]).to eq("closed")

        # Check for issues closed metric
        closed_metric = result[:metrics].find { |m| m[:name] == "github.issues.closed" }
        expect(closed_metric).to be_present

        # Check for author metric
        author_metric = result[:metrics].find { |m| m[:name] == "github.issues.by_author" }
        expect(author_metric).to be_present
        expect(author_metric[:dimensions][:author]).to eq("octocat")
      end
    end

    context "with a check_run event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "github.check_run.completed",
          source: "github",
          data: {
            repository: { full_name: "example/repo" }
          }
        )
      end

      it "returns the expected metrics" do
        result = classifier.classify(event)

        expect(result[:metrics].size).to eq(1)
        expect(result[:metrics].first[:name]).to eq("github.check_run.completed")
      end
    end

    context "with a workflow_run event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "github.workflow_run.completed",
          source: "github",
          data: {
            repository: { full_name: "example/repo" },
            workflow_run: { conclusion: "success" }
          }
        )
      end

      it "returns the expected metrics" do
        result = classifier.classify(event)

        # The enhanced classifier creates several metrics for CI events
        expect(result[:metrics].size).to be >= 2
        expect(result[:metrics].size).to be <= 5 # Reasonable upper bound

        # Check for workflow run metric
        run_metric = result[:metrics].find { |m| m[:name] == "github.workflow_run.completed" }
        expect(run_metric).to be_present

        # Check for conclusion metric
        conclusion_metric = result[:metrics].find { |m| m[:name] == "github.workflow_run.conclusion.success" }
        expect(conclusion_metric).to be_present
      end
    end

    context "with a create event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "github.create",
          source: "github",
          data: {
            repository: { full_name: "example/repo" },
            ref_type: "branch",
            ref: "feature/new-branch"
          }
        )
      end

      it "returns the expected metrics" do
        result = classifier.classify(event)

        expect(result[:metrics].size).to eq(2)

        # Check for create total metric
        total_metric = result[:metrics].find { |m| m[:name] == "github.create.total" }
        expect(total_metric).to be_present

        # Check for create branch metric
        branch_metric = result[:metrics].find { |m| m[:name] == "github.create.branch" }
        expect(branch_metric).to be_present
      end
    end

    context "with an unknown GitHub event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "github.some_event.some_action",
          source: "github",
          data: {
            repository: { full_name: "example/repo" }
          }
        )
      end

      it "returns a generic metric" do
        result = classifier.classify(event)

        expect(result[:metrics].size).to eq(1)
        expect(result[:metrics].first[:name]).to eq("github.some_event.some_action")
      end
    end

    context "without a dimension extractor" do
      let(:classifier_without_extractor) { described_class.new }
      let(:event) do
        FactoryBot.build(
          :event,
          name: "github.push",
          source: "github",
          data: {
            repository: { full_name: "example/repo" },
            commits: [{ id: "abc123" }]
          }
        )
      end

      it "still returns metrics with default values" do
        result = classifier_without_extractor.classify(event)

        expect(result[:metrics]).to be_an(Array)
        expect(result[:metrics].size).to eq(4)

        # Check that dimensions are empty or use default values
        total_metric = result[:metrics].find { |m| m[:name] == "github.push.total" }
        expect(total_metric[:dimensions]).to eq({})

        commits_metric = result[:metrics].find { |m| m[:name] == "github.push.commits" }
        expect(commits_metric[:value]).to eq(1) # Default value
      end
    end

    context "with push event containing timestamps" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "github.push",
          source: "github",
          data: {
            repository: { full_name: "example/repo" },
            commits: [
              {
                id: "commit1",
                message: "feat(users): add login feature",
                timestamp: "2023-01-15T12:00:00Z",
                added: ["src/login.rb"],
                modified: [],
                removed: []
              },
              {
                id: "commit2",
                message: "fix(users): fix login bug",
                timestamp: "2023-01-15T14:30:00Z",
                added: [],
                modified: ["src/login.rb"],
                removed: []
              },
              {
                id: "commit3",
                message: "test(users): add login tests",
                timestamp: "2023-01-16T09:15:00Z",
                added: ["test/login_test.rb"],
                modified: [],
                removed: []
              },
              {
                id: "commit4",
                message: "Invalid commit with no conventional format",
                timestamp: "2023-01-17T10:20:00Z",
                added: [],
                modified: ["README.md"],
                removed: []
              },
              {
                id: "commit5",
                message: "docs: update documentation",
                # Deliberately missing timestamp to test graceful handling
                added: [],
                modified: ["docs/README.md"],
                removed: []
              }
            ],
            ref: "refs/heads/main",
            sender: { login: "developer" }
          }
        )
      end

      it "creates daily commit volume metrics from commit timestamps" do
        result = classifier.classify(event)

        # Find all daily commit volume metrics
        daily_metrics = result[:metrics].select { |m| m[:name] == "github.commit_volume.daily" }

        # Should have metrics for 3 different days
        expect(daily_metrics.size).to eq(3)

        # Check Jan 15 metric (2 commits)
        jan15_metric = daily_metrics.find { |m| m[:dimensions][:date] == "2023-01-15" }
        expect(jan15_metric).to be_present
        expect(jan15_metric[:value]).to eq(2)
        expect(jan15_metric[:timestamp]).to eq(Date.parse("2023-01-15").to_time)
        expect(jan15_metric[:dimensions][:commit_date]).to eq("2023-01-15")
        expect(jan15_metric[:dimensions][:delivery_date]).to be_present

        # Check Jan 16 metric (1 commit)
        jan16_metric = daily_metrics.find { |m| m[:dimensions][:date] == "2023-01-16" }
        expect(jan16_metric).to be_present
        expect(jan16_metric[:value]).to eq(1)
        expect(jan16_metric[:timestamp]).to eq(Date.parse("2023-01-16").to_time)
        expect(jan16_metric[:dimensions][:commit_date]).to eq("2023-01-16")
        expect(jan16_metric[:dimensions][:delivery_date]).to be_present

        # Check Jan 17 metric (1 commit)
        jan17_metric = daily_metrics.find { |m| m[:dimensions][:date] == "2023-01-17" }
        expect(jan17_metric).to be_present
        expect(jan17_metric[:value]).to eq(1)
        expect(jan17_metric[:timestamp]).to eq(Date.parse("2023-01-17").to_time)
        expect(jan17_metric[:dimensions][:commit_date]).to eq("2023-01-17")
        expect(jan17_metric[:dimensions][:delivery_date]).to be_present
      end

      it "handles missing or invalid timestamps gracefully" do
        # Create an event with invalid timestamp formats
        invalid_timestamp_event = FactoryBot.build(
          :event,
          name: "github.push",
          source: "github",
          data: {
            repository: { full_name: "example/repo" },
            commits: [
              {
                id: "invalid1",
                message: "Test commit with invalid timestamp",
                timestamp: "not-a-timestamp",
                added: ["test.rb"]
              },
              {
                id: "invalid2",
                message: "Test commit with empty timestamp",
                timestamp: "",
                added: ["test2.rb"]
              },
              {
                id: "valid",
                message: "Valid commit",
                timestamp: "2023-01-20T15:30:00Z",
                added: ["valid.rb"]
              }
            ],
            ref: "refs/heads/main"
          }
        )

        # Should not raise any errors
        result = classifier.classify(invalid_timestamp_event)

        # Should only have one daily metric for the valid timestamp
        daily_metrics = result[:metrics].select { |m| m[:name] == "github.commit_volume.daily" }
        expect(daily_metrics.size).to eq(1)
        expect(daily_metrics.first[:dimensions][:date]).to eq("2023-01-20")
        expect(daily_metrics.first[:value]).to eq(1)
      end
    end
  end
end
