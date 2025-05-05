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
            commits: [{ id: "abc123" }, { id: "def456" }],
            ref: "refs/heads/main",
            sender: { login: "octocat" }
          }
        )
      end

      it "returns the expected metrics" do
        result = classifier.classify(event)

        expect(result).to be_a(Hash)
        expect(result[:metrics]).to be_an(Array)
        expect(result[:metrics].size).to eq(4)

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
        author_metric = result[:metrics].find { |m| m[:name] == "github.push.unique_authors" }
        expect(author_metric).to be_present
        expect(author_metric[:dimensions][:author]).to eq("octocat")
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

        expect(result[:metrics].size).to eq(2)

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
  end
end
