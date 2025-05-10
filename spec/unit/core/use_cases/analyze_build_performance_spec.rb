# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::AnalyzeBuildPerformance do
  let(:storage_port) { instance_double("StoragePort") }
  let(:cache_port) { instance_double("CachePort") }
  let(:metric_naming_port) { instance_double("MetricNamingPort") }
  let(:logger_port) { instance_double("LoggerPort", debug: nil, info: nil, warn: nil, error: nil) }

  let(:use_case) do
    described_class.new(
      storage_port: storage_port,
      cache_port: cache_port,
      metric_naming_port: metric_naming_port,
      logger_port: logger_port
    )
  end

  # Mock data
  let(:time_period) { 30 }
  let(:repository) { "test/repo" }
  let(:start_time) { time_period.days.ago }

  # Mock metrics for the new implementation
  let(:build_metrics) do
    [
      build_metric("github.workflow_run.completed", "workflow1", "job1", "success", 120),
      build_metric("github.workflow_run.completed", "workflow1", "job2", "success", 180),
      build_metric("github.workflow_run.completed", "workflow2", "job1", "failure", 90),
      build_metric("github.workflow_run.completed", "workflow2", "job2", "success", 150)
    ]
  end

  let(:duration_metrics) do
    [
      build_metric("github.ci.build.duration", "workflow1", "job1", "success", 120, 120),
      build_metric("github.ci.build.duration", "workflow1", "job2", "success", 180, 180),
      build_metric("github.ci.build.duration", "workflow2", "job1", "failure", 90, 90),
      build_metric("github.ci.build.duration", "workflow2", "job2", "success", 150, 150)
    ]
  end

  let(:success_metrics) do
    [
      build_metric("github.workflow_run.conclusion.success", "workflow1", "job1", "success", 120),
      build_metric("github.workflow_run.conclusion.success", "workflow1", "job2", "success", 180),
      build_metric("github.workflow_run.conclusion.success", "workflow2", "job2", "success", 150)
    ]
  end

  let(:failure_metrics) do
    [
      build_metric("github.workflow_run.conclusion.failure", "workflow2", "job1", "failure", 90)
    ]
  end

  let(:workflow_duration_metrics) do
    [
      build_metric("github.workflow_run.duration", "workflow1", "job1", "success", 120, 120),
      build_metric("github.workflow_run.duration", "workflow1", "job2", "success", 180, 180),
      build_metric("github.workflow_run.duration", "workflow2", "job1", "failure", 90, 90),
      build_metric("github.workflow_run.duration", "workflow2", "job2", "success", 150, 150)
    ]
  end

  let(:check_run_metrics) do
    [
      build_metric("github.check_run.completed", "workflow1", "job1", "success", 110),
      build_metric("github.check_run.completed", "workflow2", "job1", "failure", 100)
    ]
  end

  # Mock metrics for different repositories
  let(:multi_repo_metrics) do
    [
      # First repository
      build_metric("github.workflow_run.completed", "workflow1", "job1", "success", 120, 1, "test/repo"),
      build_metric("github.workflow_run.completed", "workflow2", "job1", "failure", 90, 1, "test/repo"),
      # Second repository
      build_metric("github.workflow_run.completed", "workflow3", "job1", "success", 150, 1, "other/repo"),
      build_metric("github.workflow_run.completed", "workflow4", "job1", "success", 180, 1, "other/repo")
    ]
  end

  # Mock DomainMetric class for direct DB fallback
  let(:domain_metric_class) { class_double("DomainMetric") }
  let(:domain_metrics_relation) { double("ActiveRecord::Relation") }

  before do
    # Mock DependencyContainer for metric_naming_port
    allow(DependencyContainer).to receive(:resolve).with(:metric_naming_port).and_return(metric_naming_port)

    # Setup domain_metric_class for fallback queries
    stub_const("DomainMetric", domain_metric_class)
    allow(domain_metric_class).to receive(:where).and_return(domain_metrics_relation)
    allow(domain_metrics_relation).to receive(:where).and_return(domain_metrics_relation)
    allow(domain_metrics_relation).to receive(:count).and_return(0)
  end

  describe "#call" do
    context "when not using cache" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        # Setup the storage_port to return our test metrics
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_run.completed",
          start_time: anything
        ).and_return(build_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.build.duration",
          start_time: anything
        ).and_return(duration_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_run.conclusion.success",
          start_time: anything
        ).and_return(success_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_run.conclusion.failure",
          start_time: anything
        ).and_return(failure_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_run.duration",
          start_time: anything
        ).and_return(workflow_duration_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.check_run.completed",
          start_time: anything
        ).and_return(check_run_metrics)
      end

      it "returns build performance metrics" do
        result = use_case.call(time_period: time_period)

        expect(result).to include(
          total: 4,
          success_rate: 75.0,
          avg_duration: 135.0
        )
      end

      it "includes time series data" do
        result = use_case.call(time_period: time_period)

        expect(result[:builds_by_day]).to be_a(Hash)
        expect(result[:success_by_day]).to be_a(Hash)
      end

      it "includes workflow-specific metrics" do
        result = use_case.call(time_period: time_period)

        expect(result[:builds_by_workflow]).to include("workflow1" => 2, "workflow2" => 2)
        expect(result[:longest_workflow_durations].keys).to include("workflow1", "workflow2")
      end

      it "identifies flaky builds" do
        # Create some flaky build data with multiple transitions
        flaky_metrics = [
          build_metric("github.workflow_run.completed", "flaky_workflow", "job1", "success", 100),
          build_metric("github.workflow_run.completed", "flaky_workflow", "job1", "failure", 110),
          build_metric("github.workflow_run.completed", "flaky_workflow", "job1", "success", 120),
          build_metric("github.workflow_run.completed", "flaky_workflow", "job1", "failure", 130)
        ]

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_run.completed",
          start_time: anything
        ).and_return(flaky_metrics)

        result = use_case.call(time_period: time_period)

        expect(result[:flaky_builds]).to be_an(Array)
        expect(result[:flaky_builds].size).to be > 0
        expect(result[:flaky_builds].first).to include(
          workflow_name: "flaky_workflow",
          job_name: "job1"
        )
      end

      it "calculates properly when there are no duration metrics" do
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.build.duration",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_run.duration",
          start_time: anything
        ).and_return([])

        result = use_case.call(time_period: time_period)

        expect(result[:avg_duration]).to eq(0)
      end
    end

    context "when filtering by repository" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        # Set default empty response for any list_metrics call
        allow(storage_port).to receive(:list_metrics).with(any_args).and_return([])

        # Set up repository-specific metrics
        repo_build_metrics = build_metrics.select { |m| m.dimensions["repository"] == repository }

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_run.completed",
          start_time: anything
        ).and_return(repo_build_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.build.duration",
          start_time: anything
        ).and_return(duration_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_run.conclusion.success",
          start_time: anything
        ).and_return(success_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_run.conclusion.failure",
          start_time: anything
        ).and_return(failure_metrics)
      end

      it "filters metrics by repository" do
        result = use_case.call(time_period: time_period, repository: repository)

        expect(result).to include(:total)
        expect(result).to include(:success_rate)
        expect(result).to include(:avg_duration)
      end

      it "properly filters metrics across multiple repositories" do
        # Set up multi-repository metrics
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_run.completed",
          start_time: anything
        ).and_return(multi_repo_metrics)

        # Call with specific repository filter
        result = use_case.call(time_period: time_period, repository: "test/repo")

        # Should only include metrics from test/repo (2 workflows)
        expect(result[:total]).to eq(2)

        # Call with different repository filter
        result = use_case.call(time_period: time_period, repository: "other/repo")

        # Should only include metrics from other/repo (2 workflows)
        expect(result[:total]).to eq(2)
      end
    end

    context "when no metrics are found" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        # Return empty arrays for all metric queries
        allow(storage_port).to receive(:list_metrics).with(any_args).and_return([])

        # Set up direct DB fallback
        allow(domain_metric_class).to receive(:where).with(name: "github.workflow_run.completed").and_return(domain_metrics_relation)
        allow(domain_metric_class).to receive(:where).with(name: "github.workflow_run.conclusion.success").and_return(domain_metrics_relation)
        allow(domain_metric_class).to receive(:where).with(name: "github.workflow_run.conclusion.failure").and_return(domain_metrics_relation)

        allow(domain_metrics_relation).to receive(:where).with("recorded_at >= ?",
                                                               anything).and_return(domain_metrics_relation)
        allow(domain_metrics_relation).to receive(:count).and_return(10, 7, 3) # completed, success, failure counts
      end

      it "falls back to direct DB queries" do
        result = use_case.call(time_period: time_period)

        expect(result[:total]).to eq(10)
        expect(result[:success_rate]).to eq(70.0) # 7/10 * 100 rounded to 1 decimal place
      end

      it "handles the case when all metrics are zero" do
        allow(domain_metrics_relation).to receive(:count).and_return(0, 0, 0) # all zeroes

        result = use_case.call(time_period: time_period)

        expect(result[:total]).to eq(0)
        expect(result[:success_rate]).to eq(0)
      end
    end

    context "when using cache" do
      let(:cache_key) { "build_performance:days_30:repo_test_repo" }
      let(:cached_result) { { total: 10, success_rate: 90.0 }.to_json }

      before do
        allow(cache_port).to receive(:read).with(cache_key).and_return(cached_result)
        allow(storage_port).to receive(:list_metrics).with(any_args).and_return([])
      end

      it "returns cached results when available" do
        result = use_case.call(time_period: time_period, repository: repository)

        expect(result).to include(total: 10, success_rate: 90.0)
        expect(storage_port).not_to have_received(:list_metrics)
      end

      it "caches results when not in cache" do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        allow(storage_port).to receive(:list_metrics).with(any_args).and_return([])

        use_case.call(time_period: time_period, repository: repository)

        expect(cache_port).to have_received(:write).with(
          anything,
          anything,
          expires_in: 1.hour
        )
      end

      it "handles invalid JSON in the cache" do
        invalid_json = "{ invalid_json: }"
        allow(cache_port).to receive(:read).with(anything).and_return(invalid_json)

        # It should proceed normally with metric collection since cache parsing failed
        allow(storage_port).to receive(:list_metrics).with(any_args).and_return([])

        # Also allow cache writing since it will try to write the new results
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        result = use_case.call(time_period: time_period)

        # Should have attempted to read metrics since cache was invalid
        expect(storage_port).to have_received(:list_metrics).at_least(:once)
      end
    end

    context "when using fallback data sources" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        # First queries return empty arrays to trigger fallback
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_run.completed",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.build.duration",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_run.conclusion.success",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_run.conclusion.failure",
          start_time: anything
        ).and_return([])

        # Fallback to workflow duration metrics
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_run.duration",
          start_time: anything
        ).and_return(workflow_duration_metrics)

        # Fallback to check run metrics
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.check_run.completed",
          start_time: anything
        ).and_return(check_run_metrics)
      end

      it "falls back to alternative metrics when primary ones aren't available" do
        result = use_case.call(time_period: time_period)

        # Since we're using check_run_metrics as fallback, we should have data
        expect(result[:total]).to be > 0
        expect(result).to include(:success_rate)
      end

      it "filters metrics by conclusion in the fallback path" do
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.check_run.completed",
          start_time: anything
        ).and_return(check_run_metrics)

        result = use_case.call(time_period: time_period)

        # Should have classified check runs by their conclusion
        success_count = check_run_metrics.count { |m| m.dimensions["conclusion"] == "success" }
        expect(result[:success_rate]).to eq((success_count.to_f / check_run_metrics.size * 100).round(2))
      end
    end
  end

  # Helper methods
  def build_metric(name, workflow_name, job_name, conclusion, timestamp_offset = 0, value = 1, repo = repository)
    dimensions = {
      "repository" => repo,
      "workflow_name" => workflow_name,
      "job_name" => job_name,
      "conclusion" => conclusion
    }

    instance_double(
      "Domain::Metric",
      id: SecureRandom.uuid,
      name: name,
      value: value,
      dimensions: dimensions,
      timestamp: Time.now - timestamp_offset.seconds
    )
  end
end
