require "rails_helper"

RSpec.describe UseCases::CalculateMetrics do
  subject(:use_case) do
    described_class.new(
      storage_port: mock_storage_port,
      cache_port: mock_cache_port,
      metric_classifier: mock_metric_classifier,
      dimension_extractor: mock_dimension_extractor,
      team_repository_port: mock_team_repository_port
    )
  end

  include_context "with all mock ports"
  include_context "event examples"
  include_context "metric examples"

  let(:mock_metric_classifier) do
    instance_double(Domain::MetricClassifier).tap do |classifier|
      allow(classifier).to receive(:classify_event).and_return({
                                                                 metrics: [
                                                                   {
                                                                     name: "#{event.name}_count",
                                                                     value: 1,
                                                                     dimensions: { source: event.source }
                                                                   }
                                                                 ]
                                                               })
    end
  end

  let(:mock_dimension_extractor) do
    instance_double(Domain::Extractors::DimensionExtractor).tap do |extractor|
      allow(extractor).to receive(:extract_org_from_repo).and_return("test-org")
      allow(extractor).to receive(:extract_file_changes).and_return({
                                                                      files_added: 0,
                                                                      files_modified: 0,
                                                                      files_removed: 0,
                                                                      directory_hotspots: {},
                                                                      extension_hotspots: {}
                                                                    })
      allow(extractor).to receive(:extract_code_volume).and_return({
                                                                     code_additions: 0,
                                                                     code_deletions: 0,
                                                                     code_churn: 0
                                                                   })
    end
  end

  let(:team) do
    Domain::Team.new(
      id: 1,
      name: "test-org",
      slug: "test-org",
      description: "Auto-created team"
    )
  end

  let(:event) do
    Domain::EventFactory.create(
      id: "event-123",
      name: "github.push",
      data: {
        repository: { full_name: "test-org/test-repo", html_url: "https://github.com/test-org/test-repo" },
        value: 85.5,
        host: "web-01",
        region: "us-west"
      },
      source: "github"
    )
  end

  before do
    # Configure mock storage port to return the event
    allow(mock_storage_port).to receive(:find_event).with(event.id).and_return(event)

    # Mock save_metric to return a metric with an ID
    allow(mock_storage_port).to receive(:save_metric) do |metric|
      metric.with_id("metric-123")
    end

    # Allow cache_port to receive write messages
    allow(mock_cache_port).to receive(:write).with(anything, anything, anything)

    # Configure mock team repository
    allow(mock_team_repository_port).to receive(:find_team_by_slug).and_return(nil)
    allow(mock_team_repository_port).to receive(:save_team).and_return(team)
    allow(mock_team_repository_port).to receive(:find_repository_by_name).and_return(nil)
    allow(mock_team_repository_port).to receive(:save_repository).and_return(
      Domain::CodeRepository.new(
        id: 1,
        name: "test-org/test-repo",
        url: "https://github.com/test-org/test-repo",
        provider: "github",
        team_id: 1
      )
    )

    # Mock Team.first for default team handling
    allow(Team).to receive(:first).and_return(nil)
  end

  describe "#call" do
    it "finds the event and classifies it" do
      use_case.call(event.id)
      expect(mock_storage_port).to have_received(:find_event).with(event.id)
      expect(mock_metric_classifier).to have_received(:classify_event).with(event)
    end

    it "creates metrics from the classification" do
      use_case.call(event.id)
      expect(mock_storage_port).to have_received(:save_metric).at_least(:once)
      expect(mock_cache_port).to have_received(:write).at_least(:once)
    end

    it "returns the created metrics" do
      result = use_case.call(event.id)
      expect(result).to be_a(Domain::Metric).or be_a(Array)
    end

    it "adds repository dimension to metrics that don't have it" do
      result = use_case.call(event.id)

      expect(mock_storage_port).to have_received(:save_metric) do |metric|
        expect(metric.dimensions[:repository]).to eq("test-org/test-repo")
      end
    end

    it "adds organization dimension to metrics based on repository name" do
      result = use_case.call(event.id)

      expect(mock_storage_port).to have_received(:save_metric) do |metric|
        expect(metric.dimensions[:organization]).to eq("test-org")
      end
    end

    it "attempts to register the repository and team" do
      use_case.call(event.id)

      # Should attempt to create the team based on the organization name
      expect(mock_team_repository_port).to have_received(:find_team_by_slug).with("test-org")
      expect(mock_team_repository_port).to have_received(:save_team)

      # Should attempt to register the repository with the team
      expect(mock_team_repository_port).to have_received(:find_repository_by_name).with("test-org/test-repo").at_least(:once)
      expect(mock_team_repository_port).to have_received(:save_repository) do |repo|
        expect(repo.name).to eq("test-org/test-repo")
        expect(repo.team_id).to eq(1)
      end
    end

    context "when repository already exists with a team" do
      let(:existing_repo) do
        Domain::CodeRepository.new(
          id: 2,
          name: "test-org/test-repo",
          provider: "github",
          team_id: 5 # Already associated with a different team
        )
      end

      before do
        allow(mock_team_repository_port).to receive(:find_repository_by_name).and_return(existing_repo)
      end

      it "respects the existing team assignment" do
        use_case.call(event.id)

        expect(mock_team_repository_port).to have_received(:save_repository) do |repo|
          expect(repo.team_id).to eq(5) # Should keep existing team ID
        end
      end
    end
  end

  describe "factory method" do
    it "creates the use case with dependencies injected" do
      # Register our mocks with the container
      DependencyContainer.register(:storage_port, mock_storage_port)
      DependencyContainer.register(:cache_port, mock_cache_port)
      DependencyContainer.register(:metric_classifier, mock_metric_classifier)
      DependencyContainer.register(:dimension_extractor, mock_dimension_extractor)
      DependencyContainer.register(:team_repository, mock_team_repository_port)

      # Register the repositories needed by the composite adapter
      DependencyContainer.register(:event_repository, mock_storage_port)
      DependencyContainer.register(:metric_repository, mock_storage_port)

      # Create use case using factory
      factory_created = UseCaseFactory.create_calculate_metrics

      # Verify injected dependencies are working
      result = factory_created.call(event.id)
      expect(result).to be_a(Domain::Metric)
      expect(mock_storage_port).to have_received(:save_metric).at_least(:once)
    end
  end
end
