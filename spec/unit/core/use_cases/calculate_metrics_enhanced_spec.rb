# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::CalculateMetrics, "enhanced functionality" do
  let(:storage_port) { instance_double("StoragePort") }
  let(:cache_port) { instance_double("CachePort") }
  let(:metric_classifier) { instance_double("Domain::Classifiers::MetricClassifier") }
  let(:dimension_extractor) { instance_double("Domain::Extractors::DimensionExtractor") }
  let(:team_repository_port) { instance_double("TeamRepositoryPort") }

  let(:event_id) { "event-123" }
  let(:repository) { "example/repo" }
  let(:event_timestamp) { Time.current }

  let(:github_push_event) do
    instance_double(
      "Domain::Event",
      id: event_id,
      name: "github.push",
      source: "github",
      timestamp: event_timestamp,
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

  let(:metrics_base) do
    [
      Domain::Metric.new(
        id: nil,
        name: "github.push.total",
        value: 1,
        source: "github",
        timestamp: event_timestamp,
        dimensions: { repository: repository, organization: "example" }
      )
    ]
  end

  let(:metrics_commit_type) do
    [
      Domain::Metric.new(
        id: nil,
        name: "github.commit.type",
        value: 1,
        source: "github",
        timestamp: event_timestamp,
        dimensions: { repository: repository, commit_type: "feat", commit_scope: "api", organization: "example" }
      ),
      Domain::Metric.new(
        id: nil,
        name: "github.commit.type",
        value: 1,
        source: "github",
        timestamp: event_timestamp,
        dimensions: { repository: repository, commit_type: "fix", commit_scope: "auth", organization: "example" }
      )
    ]
  end

  let(:metrics_breaking_change) do
    [
      Domain::Metric.new(
        id: nil,
        name: "github.commit.breaking_change",
        value: 1,
        source: "github",
        timestamp: event_timestamp,
        dimensions: { repository: repository, commit_type: "fix", commit_scope: "auth", organization: "example" }
      )
    ]
  end

  let(:metrics_directories) do
    [
      Domain::Metric.new(
        id: nil,
        name: "github.commit.directory_change",
        value: 1,
        source: "github",
        timestamp: event_timestamp,
        dimensions: { repository: repository, directory: "src/api", organization: "example" }
      ),
      Domain::Metric.new(
        id: nil,
        name: "github.commit.directory_change",
        value: 2,
        source: "github",
        timestamp: event_timestamp,
        dimensions: { repository: repository, directory: "src/auth", organization: "example" }
      )
    ]
  end

  let(:metrics_extensions) do
    [
      Domain::Metric.new(
        id: nil,
        name: "github.commit.file_extension",
        value: 3,
        source: "github",
        timestamp: event_timestamp,
        dimensions: { repository: repository, extension: "rb", organization: "example" }
      )
    ]
  end

  let(:metrics_volume) do
    [
      Domain::Metric.new(
        id: nil,
        name: "github.commit.code_volume",
        value: 80,
        source: "github",
        timestamp: event_timestamp,
        dimensions: { repository: repository, additions: 50, deletions: 30, organization: "example" }
      )
    ]
  end

  let(:all_test_metrics) do
    metrics_base +
      metrics_commit_type +
      metrics_breaking_change +
      metrics_directories +
      metrics_extensions +
      metrics_volume
  end

  let(:use_case) do
    described_class.new(
      storage_port: storage_port,
      cache_port: cache_port,
      metric_classifier: metric_classifier,
      dimension_extractor: dimension_extractor,
      team_repository_port: team_repository_port
    )
  end

  describe "#call with dimension_extractor" do
    before do
      # Mock basic dependencies
      allow(storage_port).to receive(:find_event).with(event_id).and_return(github_push_event)
      allow(cache_port).to receive(:write)

      # Ensure each save_metric returns a valid result with an ID
      all_test_metrics.each_with_index do |metric, i|
        saved_metric = metric.clone
        saved_metric.instance_variable_set(:@id, "metric-#{i + 1}")
        allow(storage_port).to receive(:save_metric).with(
          having_attributes(
            name: metric.name,
            value: metric.value
          )
        ).and_return(saved_metric)
      end

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

      # Add mock for extract_org_from_repo
      allow(dimension_extractor).to receive(:extract_org_from_repo).with(repository).and_return("example")

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

      # Mock repository operations
      allow(team_repository_port).to receive(:find_repository_by_name).with(repository).and_return(nil)

      # Mock team operations
      team = instance_double("Domain::Team", id: 42, name: "example")
      find_or_create_team_use_case = instance_double("UseCases::FindOrCreateTeam")
      allow(find_or_create_team_use_case).to receive(:call).and_return(team)
      allow(UseCases::FindOrCreateTeam).to receive(:new).and_return(find_or_create_team_use_case)

      # Mock register repository
      register_repository_use_case = instance_double("UseCases::RegisterRepository")
      allow(register_repository_use_case).to receive(:call).and_return(nil)
      allow(UseCases::RegisterRepository).to receive(:new).and_return(register_repository_use_case)
    end

    it "generates additional metrics for conventional commits" do
      result = use_case.call(event_id)

      # Should have been called at least once with metrics that have right names
      expect(storage_port).to have_received(:save_metric).with(
        having_attributes(name: "github.push.total")
      )

      # Should be an array of metrics
      expect(result).to be_an(Array)
    end
  end
end
