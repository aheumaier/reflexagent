# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::AnalyzeBuildPerformance do
  let(:storage_port) { instance_double("StoragePort") }
  let(:cache_port) { instance_double("CachePort") }
  let(:use_case) { described_class.new(storage_port: storage_port, cache_port: cache_port) }

  # Mock data
  let(:time_period) { 30 }
  let(:repository) { "test/repo" }
  let(:start_time) { time_period.days.ago }

  # Mock metrics
  let(:build_metrics) do
    [
      build_metric("github.workflow_job.completed", "workflow1", "job1", "success", 120),
      build_metric("github.workflow_job.completed", "workflow1", "job2", "success", 180),
      build_metric("github.workflow_job.completed", "workflow2", "job1", "failure", 90),
      build_metric("github.workflow_job.completed", "workflow2", "job2", "success", 150)
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
      build_metric("github.workflow_job.conclusion.success", "workflow1", "job1", "success", 120),
      build_metric("github.workflow_job.conclusion.success", "workflow1", "job2", "success", 180),
      build_metric("github.workflow_job.conclusion.success", "workflow2", "job2", "success", 150)
    ]
  end

  let(:failure_metrics) do
    [
      build_metric("github.workflow_job.conclusion.failure", "workflow2", "job1", "failure", 90)
    ]
  end

  describe "#call" do
    context "when not using cache" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_job.completed",
          start_time: anything
        ).and_return(build_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.build.duration",
          start_time: anything
        ).and_return(duration_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_job.conclusion.success",
          start_time: anything
        ).and_return(success_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_job.conclusion.failure",
          start_time: anything
        ).and_return(failure_metrics)
      end

      it "returns build performance metrics" do
        result = use_case.call(time_period: time_period)

        expect(result).to include(
          total_builds: 4,
          successful_builds: 3,
          failed_builds: 1,
          success_rate: 75.0,
          average_build_duration: 135.0
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
          build_metric("github.workflow_job.completed", "flaky_workflow", "job1", "success", 100),
          build_metric("github.workflow_job.completed", "flaky_workflow", "job1", "failure", 110),
          build_metric("github.workflow_job.completed", "flaky_workflow", "job1", "success", 120),
          build_metric("github.workflow_job.completed", "flaky_workflow", "job1", "failure", 130)
        ]

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_job.completed",
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
    end

    context "when filtering by repository" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        allow(storage_port).to receive(:list_metrics).with(any_args).and_return([])

        # Set up filtered metrics
        repo_metrics = build_metrics.select { |m| m.dimensions["repository"] == repository }

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.workflow_job.completed",
          start_time: anything
        ).and_return(build_metrics)
      end

      it "filters metrics by repository" do
        expect(use_case.call(time_period: time_period, repository: repository)).to include(:total_builds)
      end
    end

    context "when using cache" do
      let(:cache_key) { "build_performance:days_30:repo_test_repo" }
      let(:cached_result) { { total_builds: 10, success_rate: 90.0 }.to_json }

      before do
        allow(cache_port).to receive(:read).with(cache_key).and_return(cached_result)
        allow(storage_port).to receive(:list_metrics).with(any_args).and_return([])
      end

      it "returns cached results when available" do
        result = use_case.call(time_period: time_period, repository: repository)

        expect(result).to include(total_builds: 10, success_rate: 90.0)
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
    end
  end

  # Helper methods
  def build_metric(name, workflow_name, job_name, conclusion, timestamp_offset = 0, value = 1)
    dimensions = {
      "repository" => repository,
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
