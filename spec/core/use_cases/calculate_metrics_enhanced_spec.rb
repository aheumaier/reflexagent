# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::CalculateMetrics, "enhanced functionality" do
  let(:storage_port) { instance_double("StoragePort") }
  let(:cache_port) { instance_double("CachePort") }
  let(:metric_classifier) { instance_double("Domain::Classifiers::MetricClassifier") }
  let(:dimension_extractor) { instance_double("Domain::Extractors::DimensionExtractor") }

  let(:event_id) { "event-123" }
  let(:repository) { "example/repo" }

  let(:github_push_event) do
    instance_double(
      "Domain::Event",
      id: event_id,
      name: "github.push",
      source: "github",
      data: {
        repository: { full_name: repository },
        commits: [
          {
            id: "commit1",
            message: "feat(api): add new endpoint",
            added: ["src/api/endpoint.rb"],
            modified: [],
            removed: []
          },
          {
            id: "commit2",
            message: "fix(auth)!: change authentication flow",
            added: [],
            modified: ["src/auth/flow.rb"],
            removed: ["src/auth/old_flow.rb"]
          }
        ]
      }
    )
  end

  let(:use_case) do
    described_class.new(
      storage_port: storage_port,
      cache_port: cache_port,
      metric_classifier: metric_classifier,
      dimension_extractor: dimension_extractor
    )
  end

  describe "#call with dimension_extractor" do
    before do
      # Mock basic dependencies
      allow(storage_port).to receive(:find_event).with(event_id).and_return(github_push_event)

      # Create a valid metric once for testing
      example_metric = Domain::Metric.new(
        id: "metric-test-id",
        name: "example.metric",
        value: 1,
        source: "github",
        timestamp: Time.now,
        dimensions: { repository: repository }
      )

      # Return the same valid metric for every save_metric call
      allow(storage_port).to receive(:save_metric).and_return(example_metric)
      allow(cache_port).to receive(:cache_metric)

      # Mock classifier to return some basic metrics
      allow(metric_classifier).to receive(:classify_event).with(github_push_event).and_return(
        metrics: [
          {
            name: "github.push.total",
            value: 1,
            dimensions: { repository: repository }
          }
        ]
      )

      # Mock dimension extractor methods for conventional commits
      allow(dimension_extractor).to receive(:extract_conventional_commit_parts)
        .with(github_push_event.data[:commits][0])
        .and_return(
          commit_type: "feat",
          commit_scope: "api",
          commit_description: "add new endpoint",
          commit_breaking: false,
          commit_conventional: true
        )

      allow(dimension_extractor).to receive(:extract_conventional_commit_parts)
        .with(github_push_event.data[:commits][1])
        .and_return(
          commit_type: "fix",
          commit_scope: "auth",
          commit_description: "change authentication flow",
          commit_breaking: true,
          commit_conventional: true
        )

      # Mock file changes extraction
      allow(dimension_extractor).to receive(:extract_file_changes)
        .with(github_push_event)
        .and_return(
          files_added: 1,
          files_modified: 1,
          files_removed: 1,
          directory_hotspots: { "src/api" => 1, "src/auth" => 2 },
          top_directory: "src/auth",
          top_directory_count: 2,
          extension_hotspots: { "rb" => 3 },
          top_extension: "rb",
          top_extension_count: 3
        )

      # Mock code volume extraction
      allow(dimension_extractor).to receive(:extract_code_volume)
        .with(github_push_event)
        .and_return(
          code_additions: 50,
          code_deletions: 30,
          code_churn: 80
        )
    end

    it "generates additional metrics for conventional commits" do
      result = use_case.call(event_id)

      # Should have saved multiple metrics
      expect(storage_port).to have_received(:save_metric).at_least(6).times

      # Should have cached all metrics
      expect(cache_port).to have_received(:cache_metric).at_least(6).times

      # Should return an array of metrics since there are multiple
      expect(result).to be_an(Array)
      expect(result.size).to be >= 6
    end

    it "generates metrics for commit types" do
      use_case.call(event_id)

      # Check for commit type metrics
      expect(storage_port).to have_received(:save_metric).with(
        have_attributes(
          name: "github.commit.type",
          dimensions: include(
            repository: repository,
            commit_type: "feat"
          )
        )
      )

      expect(storage_port).to have_received(:save_metric).with(
        have_attributes(
          name: "github.commit.type",
          dimensions: include(
            repository: repository,
            commit_type: "fix"
          )
        )
      )
    end

    it "generates a metric for breaking changes" do
      use_case.call(event_id)

      # Check for breaking change metrics
      expect(storage_port).to have_received(:save_metric).with(
        have_attributes(
          name: "github.commit.breaking_change",
          dimensions: include(
            repository: repository,
            commit_type: "fix",
            commit_scope: "auth"
          )
        )
      )
    end

    it "generates metrics for directory hotspots" do
      use_case.call(event_id)

      # Check for directory hotspot metrics
      expect(storage_port).to have_received(:save_metric).with(
        have_attributes(
          name: "github.commit.directory_change",
          value: 1,
          dimensions: include(
            repository: repository,
            directory: "src/api"
          )
        )
      )

      expect(storage_port).to have_received(:save_metric).with(
        have_attributes(
          name: "github.commit.directory_change",
          value: 2,
          dimensions: include(
            repository: repository,
            directory: "src/auth"
          )
        )
      )
    end

    it "generates metrics for code volume" do
      use_case.call(event_id)

      # Check for code volume metrics
      expect(storage_port).to have_received(:save_metric).with(
        have_attributes(
          name: "github.commit.code_volume",
          value: 80,
          dimensions: include(
            repository: repository,
            additions: 50,
            deletions: 30
          )
        )
      )
    end

    context "when metrics already contain conventional commit data" do
      before do
        # Mock classifier to return metrics that already have conventional commit data
        allow(metric_classifier).to receive(:classify_event).with(github_push_event).and_return(
          metrics: [
            {
              name: "github.push.total",
              value: 1,
              dimensions: { repository: repository }
            },
            {
              name: "github.push.commit_type",
              value: 1,
              dimensions: { repository: repository, type: "feat" }
            }
          ]
        )
      end

      it "does not duplicate metrics for conventional commits" do
        result = use_case.call(event_id)

        # Should only save the metrics from the classifier
        expect(storage_port).to have_received(:save_metric).exactly(2).times
      end
    end
  end
end
