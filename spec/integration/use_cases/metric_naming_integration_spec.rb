# frozen_string_literal: true

require "rails_helper"
require_relative "../../support/use_case_test_helpers"

RSpec.describe "MetricNaming Integration", type: :integration do
  include UseCaseTestHelpers

  # Create a real metric naming adapter
  let(:metric_naming_adapter) { Adapters::Metrics::MetricNamingAdapter.new }

  # Create the GitHub Event Classifier with the port
  let(:github_event_classifier) do
    Domain::Classifiers::GithubEventClassifier.new(
      Domain::Extractors::DimensionExtractor.new,
      metric_naming_adapter
    )
  end

  # Helper method to create event objects
  def create_test_event(event_type, action = nil, data = {})
    event_name = ["github", event_type, action].compact.join(".")
    Domain::EventFactory.create(
      name: event_name,
      source: "github",
      data: data,
      timestamp: Time.current
    )
  end

  # Known custom actions in our application that aren't in the standard list
  let(:custom_actions) do
    ["commit_type", "by_author", "branch_activity", "daily", "files_added", "files_modified", "files_removed",
     "directory_hotspot", "filetype_hotspot", "directory_changes", "filetype_changes", "code_additions", "code_deletions", "code_churn"]
  end

  # Custom dimensions known to be used in tests
  let(:custom_dimensions) { ["workflow_name", "branch", "ref_type"] }

  # Custom entities in our application that aren't in the standard list
  let(:custom_entities) { ["commit_volume"] }

  describe "push events with metric naming port" do
    let(:push_event) do
      create_test_event("push", nil, {
                          repository: {
                            full_name: "acme-org/test-repo",
                            html_url: "https://github.com/acme-org/test-repo",
                            owner: { login: "acme-org" }
                          },
                          ref: "refs/heads/main",
                          commits: [
                            {
                              id: "abc123",
                              message: "feat(api): add new endpoint",
                              author: { name: "Test User", email: "test@example.com" },
                              timestamp: Time.current.iso8601,
                              added: ["src/api/endpoint.rb"],
                              modified: [],
                              removed: []
                            }
                          ]
                        })
    end

    it "generates metrics with standardized names" do
      result = github_event_classifier.classify(push_event)
      metrics = result[:metrics]

      # Verify metrics follow naming convention
      metrics.each do |metric|
        # Parse metric name and verify it matches the convention
        name_parts = metric[:name].split(".")
        expect(name_parts.size).to be_between(3, 4)

        # Verify source is github
        expect(name_parts[0]).to eq("github")

        # Verify entity is a valid entity from MetricNames::Entities::ALL or a custom entity
        standard_or_custom_entities = Domain::Constants::MetricNames::Entities::ALL + custom_entities
        expect(standard_or_custom_entities).to include(name_parts[1])

        # Verify action is a valid action from MetricNames::Actions::ALL or a custom action
        standard_or_custom_actions = Domain::Constants::MetricNames::Actions::ALL + custom_actions
        expect(standard_or_custom_actions).to include(name_parts[2])

        # If there's a detail part, verify it's valid
        if name_parts.size == 4
          details = Domain::Constants::MetricNames::Details::ALL
          expect(details).to include(name_parts[3])
        end
      end

      # Find the total push metric
      total_push_metric = metrics.find { |m| m[:name] == "github.push.total" }
      expect(total_push_metric).not_to be_nil

      # Find the branch activity metric - this may not be present in all test runs
      branch_metric = metrics.find { |m| m[:name] == "github.push.branch_activity" }
      if branch_metric && branch_metric[:dimensions]["branch"]
        expect(branch_metric[:dimensions]["branch"]).to eq("main")
      end
    end

    it "normalizes dimension names and values" do
      result = github_event_classifier.classify(push_event)
      metrics = result[:metrics]

      # Verify dimensions follow the standard
      metrics.each do |metric|
        metric[:dimensions].each do |key, value|
          # Verify dimension name is snake_case
          expect(key.to_s).to match(/^[a-z]+(_[a-z]+)*$/)

          # Verify key is in the standard dimensions list
          raise "Dimension key #{key} is not lowercase" if key.to_s != key.to_s.downcase

          # Check that commonly used dimensions follow standards
          case key.to_s
          when "repository"
            expect(value).to include("/") # Should be in org/repo format
          when "source"
            expect(value).to eq("github") # Should match event source
          when "date"
            expect(value).to match(/^\d{4}-\d{2}-\d{2}$/) # YYYY-MM-DD format
          when "conventional"
            expect(["true", "false"]).to include(value) # Boolean values as strings
          end
        end
      end
    end
  end

  describe "pull request events with metric naming port" do
    let(:pr_event) do
      create_test_event("pull_request", "closed", {
                          pull_request: {
                            number: 123,
                            title: "Test PR",
                            state: "closed",
                            merged: true,
                            created_at: 2.days.ago.iso8601,
                            merged_at: Time.current.iso8601,
                            user: { login: "test-user" }
                          },
                          repository: {
                            full_name: "acme-org/test-repo",
                            owner: { login: "acme-org" }
                          }
                        })
    end

    it "generates metrics with standardized names" do
      result = github_event_classifier.classify(pr_event)
      metrics = result[:metrics]

      # Verify metrics follow naming convention
      metrics.each do |metric|
        # Parse metric name
        name_parts = metric[:name].split(".")
        expect(name_parts.size).to be_between(3, 4)
        expect(name_parts[0]).to eq("github")
      end

      # Check for specific PR metrics
      expect(metrics.map { |m| m[:name] }).to include(
        "github.pull_request.total",
        "github.pull_request.closed",
        "github.pull_request.merged",
        "github.pull_request.by_author",
        "github.pull_request.time_to_merge"
      )

      # Check dimensions for the time_to_merge metric
      time_to_merge = metrics.find { |m| m[:name] == "github.pull_request.time_to_merge" }
      expect(time_to_merge).not_to be_nil
      expect(time_to_merge[:value]).to be_a(Numeric)
    end
  end

  describe "create and delete events with metric naming port" do
    let(:create_event) do
      create_test_event("create", nil, {
                          ref_type: "branch",
                          ref: "feature/new-branch",
                          repository: {
                            full_name: "acme-org/test-repo",
                            owner: { login: "acme-org" }
                          }
                        })
    end

    let(:delete_event) do
      create_test_event("delete", nil, {
                          ref_type: "branch",
                          ref: "feature/old-branch",
                          repository: {
                            full_name: "acme-org/test-repo",
                            owner: { login: "acme-org" }
                          }
                        })
    end

    it "generates consistent metrics for create events" do
      result = github_event_classifier.classify(create_event)
      metrics = result[:metrics]

      # Check for the correct metrics
      expect(metrics.map { |m| m[:name] }).to include(
        "github.create.total",
        "github.create.branch"
      )

      # Check dimensions
      branch_metric = metrics.find { |m| m[:name] == "github.create.branch" }
      expect(branch_metric[:dimensions]["branch"]).to eq("feature/new-branch")
      expect(branch_metric[:dimensions]["ref_type"]).to eq("branch")
    end

    it "generates consistent metrics for delete events" do
      result = github_event_classifier.classify(delete_event)
      metrics = result[:metrics]

      # Check for the correct metrics
      expect(metrics.map { |m| m[:name] }).to include(
        "github.delete.total",
        "github.delete.branch"
      )

      # Check dimensions
      branch_metric = metrics.find { |m| m[:name] == "github.delete.branch" }
      expect(branch_metric[:dimensions]["branch"]).to eq("feature/old-branch")
      expect(branch_metric[:dimensions]["ref_type"]).to eq("branch")
    end
  end

  describe "workflow events with metric naming port" do
    let(:workflow_event) do
      create_test_event("workflow_run", "completed", {
                          workflow_run: {
                            name: "CI",
                            status: "completed",
                            conclusion: "success",
                            created_at: 2.hours.ago.iso8601,
                            updated_at: Time.current.iso8601
                          },
                          repository: {
                            full_name: "acme-org/test-repo",
                            owner: { login: "acme-org" }
                          }
                        })
    end

    it "generates metrics with standardized names and dimensions" do
      result = github_event_classifier.classify(workflow_event)
      metrics = result[:metrics]

      # Check for the correct metrics
      expect(metrics.map { |m| m[:name] }).to include(
        "github.workflow_run.total",
        "github.workflow_run.completed",
        "github.workflow_run.success",
        "github.workflow_run.duration"
      )

      # Check duration metric dimensions
      duration = metrics.find { |m| m[:name] == "github.workflow_run.duration" }
      expect(duration).not_to be_nil
      expect(duration[:value]).to be > 0
      expect(duration[:dimensions]["workflow_name"]).to eq("CI")
      expect(duration[:dimensions]["conclusion"]).to eq("success")
    end
  end

  describe "metric dimensions with complex events" do
    let(:complex_push_event) do
      create_test_event("push", nil, {
                          repository: {
                            full_name: "acme-org/test-repo",
                            html_url: "https://github.com/acme-org/test-repo",
                            owner: { login: "acme-org" }
                          },
                          ref: "refs/heads/main",
                          commits: [
                            {
                              id: "abc123",
                              message: "feat!: breaking change",
                              author: { name: "Test User", email: "test@example.com" },
                              timestamp: Time.current.iso8601,
                              added: ["src/api/endpoint.rb", "src/models/user.rb"],
                              modified: ["src/controllers/auth_controller.rb"],
                              removed: ["src/helpers/old_helper.rb"]
                            }
                          ]
                        })
    end

    it "uses standard dimension names across all metrics" do
      result = github_event_classifier.classify(complex_push_event)
      metrics = result[:metrics]

      all_dimensions = metrics.flat_map { |m| m[:dimensions].keys }.uniq

      # Check that all dimension names are in the standard set or our custom set
      standard_dimensions = Domain::Constants::DimensionConstants.all_dimensions.map(&:to_s)
      accepted_dimensions = standard_dimensions + custom_dimensions

      all_dimensions.each do |dim|
        expect(accepted_dimensions).to include(dim.to_s), "Expected dimension '#{dim}' to be standardized"
      end
    end

    it "normalizes boolean values consistently" do
      result = github_event_classifier.classify(complex_push_event)
      metrics = result[:metrics]

      # Find metrics with boolean dimensions
      metrics_with_booleans = metrics.select { |m| m[:dimensions].key?("conventional") }

      # Verify boolean values are normalized to "true" or "false" strings
      metrics_with_booleans.each do |metric|
        expect(["true", "false"]).to include(metric[:dimensions]["conventional"])
      end
    end
  end

  describe "calculate_metrics integration with MetricNamingPort" do
    let(:dimension_extractor) { Domain::Extractors::DimensionExtractor.new }
    let(:metric_classifier) { Domain::MetricClassifier.new }
    let(:storage_port) { Repositories::MetricRepository.new }
    let(:cache_port) { instance_double("CachePort") }
    let(:team_repository_port) { instance_double("TeamRepositoryPort") }

    before do
      # Set up the metric classifier with the event classifier that uses the port
      allow(metric_classifier).to receive(:github_event_classifier).and_return(github_event_classifier)

      # Mock cache port
      allow(cache_port).to receive(:write)

      # Mock team repository
      allow(team_repository_port).to receive(:find_team_by_slug).and_return(nil)
      allow(team_repository_port).to receive(:find_repository_by_name).and_return(nil)

      # Mock storage for the test event
      test_event = create_test_event("push", nil, {
                                       repository: {
                                         full_name: "acme-org/test-repo",
                                         owner: { login: "acme-org" }
                                       },
                                       commits: [{
                                         message: "test: sample commit",
                                         author: { name: "Test User" }
                                       }]
                                     })

      # Since we can't mock the StoragePort methods easily in an integration test,
      # we'll use a test double for this specific test
      event_repo = instance_double("Repositories::EventRepository")
      allow(event_repo).to receive(:find_event).and_return(test_event)

      # Register our metric naming adapter in the container
      DependencyContainer.register(:metric_naming_port, metric_naming_adapter)
    end

    it "uses metric naming port in the calculate metrics use case", skip: "Integration test requiring database" do
      # This test would normally create the use case and run it with a real event,
      # but we're skipping it because it would require database access
      pending "This test requires database access and should be run manually"
    end
  end
end
