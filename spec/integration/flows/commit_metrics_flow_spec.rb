# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CommitMetricsFlow", type: :integration do
  describe "directory and filetype metrics flow" do
    let(:extractor) { Domain::Extractors::DimensionExtractor.new }
    let(:classifier) { Domain::Classifiers::GithubEventClassifier.new(extractor) }
    let(:repository) { Repositories::MetricRepository.new }

    let(:test_event) do
      Domain::Event.new(
        name: "github.push",
        source: "test_integration",
        data: {
          repository: { name: "test-repo" },
          commits: [
            {
              message: "test commit 1",
              added: ["app/controllers/test_controller.rb", "app/models/test_model.rb"],
              modified: ["config/routes.rb"],
              removed: []
            },
            {
              message: "test commit 2",
              added: ["app/views/test.html.erb", "public/images/test.png"],
              modified: ["README.md"],
              removed: ["tmp/old_file.txt"]
            }
          ]
        }
      )
    end

    # Clean up test metrics before and after the test
    before do
      cleanup_test_metrics

      # Mock the dependency container to return our repository
      allow(DependencyContainer).to receive(:resolve).with(:metric_repository).and_return(repository)

      # Mock the ServiceFactory to use our repository
      allow(ServiceFactory).to receive(:create_metrics_service).and_return(
        MetricsService.new(storage_port: repository, cache_port: repository)
      )
    end

    after do
      cleanup_test_metrics
    end

    def cleanup_test_metrics
      # Remove all metrics created by the test
      DomainMetric.where("dimensions->>'source' = ?", "test_integration").delete_all

      # Also clean up any aggregated metrics that might reference these
      DomainMetric.where("name LIKE ? AND dimensions->>'source' = ?",
                         "%.daily", "test_integration").delete_all
      DomainMetric.where("name LIKE ? AND dimensions->>'source' = ?",
                         "%.5min", "test_integration").delete_all
    end

    it "processes push events and generates directory and filetype metrics" do
      # Step 1: Generate and save metrics
      result = classifier.classify(test_event)
      metrics = result[:metrics]

      expect(metrics).not_to be_empty
      expect(metrics.any? { |m| m[:name] == "github.push.directory_changes" }).to be true
      expect(metrics.any? { |m| m[:name] == "github.push.filetype_changes" }).to be true

      saved_metrics = []
      metrics.each do |metric_hash|
        metric = Domain::Metric.new(
          name: metric_hash[:name],
          value: metric_hash[:value],
          source: metric_hash[:dimensions][:source],
          dimensions: metric_hash[:dimensions],
          timestamp: Time.current
        )

        saved_metric = repository.save_metric(metric)
        saved_metrics << saved_metric
      end

      expect(saved_metrics.size).to eq(metrics.size)

      # Step 2: Run the aggregation jobs
      job = MetricAggregationJob.new
      job.perform("5min")
      job.perform("daily")

      # Step 3: Verify metrics in the database
      # Directory metrics
      dir_metrics = DomainMetric.where(
        "name = ? AND dimensions @> ?",
        "github.push.directory_changes.daily",
        { source: "test_integration" }.to_json
      )

      expect(dir_metrics).not_to be_empty
      expect(dir_metrics.find { |m| m.dimensions["directory"] == "app" }).to be_present
      expect(dir_metrics.find { |m| m.dimensions["directory"] == "app/models" }).to be_present

      # File type metrics
      file_metrics = DomainMetric.where(
        "name = ? AND dimensions @> ?",
        "github.push.filetype_changes.daily",
        { source: "test_integration" }.to_json
      )

      expect(file_metrics).not_to be_empty
      expect(file_metrics.find { |m| m.dimensions["filetype"] == "rb" }).to be_present

      # Step 4: Test controller
      controller = Dashboards::CommitMetricsController.new
      controller.instance_variable_set(:@days, 30)

      metrics_data = controller.send(:fetch_commit_metrics, 30)

      expect(metrics_data[:directory_hotspots]).not_to be_empty
      expect(metrics_data[:file_extension_hotspots]).not_to be_empty

      # Verify directory hotspots data structure
      expect(metrics_data[:directory_hotspots].first).to have_key(:directory)
      expect(metrics_data[:directory_hotspots].first).to have_key(:count)

      # Verify file extension hotspots data structure
      expect(metrics_data[:file_extension_hotspots].first).to have_key(:extension)
      expect(metrics_data[:file_extension_hotspots].first).to have_key(:count)
    end
  end
end
