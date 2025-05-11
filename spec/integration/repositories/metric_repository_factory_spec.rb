# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Metric Repository Factory", type: :integration do
  let(:factory) { Repositories::MetricRepositoryFactory.new }

  describe "factory initialization and repository creation" do
    it "creates repositories of the correct types", :aggregate_failures do
      expect(factory.base_repository).to be_a(Repositories::BaseMetricRepository)
      expect(factory.git_repository).to be_a(Repositories::GitMetricRepository)
      expect(factory.dora_repository).to be_a(Repositories::DoraMetricsRepository)
      expect(factory.issue_repository).to be_a(Repositories::IssueMetricRepository)
      expect(factory.legacy_repository).to be_a(Repositories::MetricRepository)
    end

    it "correctly injects dependencies into repositories" do
      # Get logger from a repository to test dependency injection
      base_repo = factory.base_repository
      logger = base_repo.instance_variable_get(:@logger_port)

      # Verify it's the Rails logger (default)
      expect(logger).to eq(Rails.logger)
    end
  end

  describe "repository operation via factory" do
    it "allows accessing repository functionality" do
      # Create a test metric
      test_metric = Domain::Metric.new(
        name: "test.metric.value",
        value: 42.0,
        source: "test",
        dimensions: { "test_dim" => "test_value" },
        timestamp: Time.current
      )

      # Mock the database interaction
      allow(DomainMetric).to receive(:create!).and_return(
        instance_double("DomainMetric",
                        id: 1,
                        name: test_metric.name,
                        value: test_metric.value,
                        source: test_metric.source,
                        dimensions: test_metric.dimensions,
                        recorded_at: test_metric.timestamp)
      )

      # Use the base repository via factory to save the metric
      result = factory.base_repository.save_metric(test_metric)

      # Verify the result
      expect(result).to be_a(Domain::Metric)
      expect(result.id).to eq("1")
      expect(result.name).to eq(test_metric.name)
      expect(result.value).to eq(test_metric.value)
    end
  end

  describe "repository caching" do
    it "returns the same repository instance on repeated calls" do
      # Get repositories twice
      base_repo1 = factory.base_repository
      base_repo2 = factory.base_repository

      git_repo1 = factory.git_repository
      git_repo2 = factory.git_repository

      # Verify they're the same instances
      expect(base_repo1.object_id).to eq(base_repo2.object_id)
      expect(git_repo1.object_id).to eq(git_repo2.object_id)
    end

    it "creates new repository instances after clearing the cache" do
      # Get a repository
      base_repo1 = factory.base_repository

      # Clear the cache
      factory.clear_cache

      # Get the repository again
      base_repo2 = factory.base_repository

      # Verify they're different instances
      expect(base_repo1.object_id).not_to eq(base_repo2.object_id)
    end
  end

  describe "usage in cross-repository scenarios" do
    it "enables sharing common dependencies across repositories" do
      # Create a custom logger
      custom_logger = double("CustomLogger", debug: nil, info: nil, warn: nil, error: nil)

      # Create a factory with the custom logger
      custom_factory = Repositories::MetricRepositoryFactory.new(logger_port: custom_logger)

      # Get repositories
      base_repo = custom_factory.base_repository
      git_repo = custom_factory.git_repository
      dora_repo = custom_factory.dora_repository

      # Verify they all use the same logger
      expect(base_repo.instance_variable_get(:@logger_port)).to eq(custom_logger)
      expect(git_repo.instance_variable_get(:@logger_port)).to eq(custom_logger)
      expect(dora_repo.instance_variable_get(:@logger_port)).to eq(custom_logger)
    end
  end
end
