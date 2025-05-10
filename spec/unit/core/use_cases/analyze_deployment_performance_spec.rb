# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::AnalyzeDeploymentPerformance do
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

  # Mock metrics
  let(:deploy_duration_metrics) do
    [
      build_metric("github.ci.deploy.duration", "workflow1", "deploy-prod", "success", 120, 120),
      build_metric("github.ci.deploy.duration", "workflow1", "deploy-staging", "success", 180, 80),
      build_metric("github.ci.deploy.duration", "workflow2", "deploy-prod", "failure", 90, 150),
      build_metric("github.ci.deploy.duration", "workflow2", "deploy-dev", "success", 150, 60)
    ]
  end

  let(:deployment_duration_metrics) do
    [
      build_metric("github.deployment.duration", "workflow1", "deploy-prod", "success", 120, 100)
    ]
  end

  let(:success_metrics) do
    [
      build_metric("github.ci.deploy.completed", "workflow1", "deploy-prod", "success", 120),
      build_metric("github.ci.deploy.completed", "workflow1", "deploy-staging", "success", 180),
      build_metric("github.ci.deploy.completed", "workflow2", "deploy-dev", "success", 150)
    ]
  end

  let(:deployment_status_success_metrics) do
    [
      build_metric("github.deployment_status.success", "workflow1", "deploy-prod", "success", 120)
    ]
  end

  let(:failure_metrics) do
    [
      build_metric("github.ci.deploy.failed", "workflow2", "deploy-prod", "failure", 90)
    ]
  end

  let(:deployment_status_failure_metrics) do
    [
      build_metric("github.deployment_status.failure", "workflow2", "deploy-prod", "failure", 90)
    ]
  end

  let(:deploy_frequency_metrics) do
    [
      build_metric("dora.deployment_frequency", "workflow1", "deploy-prod", "success", 120),
      build_metric("dora.deployment_frequency", "workflow1", "deploy-staging", "success", 180),
      build_metric("dora.deployment_frequency", "workflow2", "deploy-prod", "failure", 90),
      build_metric("dora.deployment_frequency", "workflow2", "deploy-dev", "success", 150)
    ]
  end

  let(:deployment_created_metrics) do
    [
      build_metric("github.deployment.created", "workflow1", "deploy-prod", "success", 120)
    ]
  end

  let(:change_failure_rate_metrics) do
    [
      build_metric("dora.change_failure_rate", "workflow2", "deploy-prod", "failure", 90, 1, repository,
                   { "reason" => "timeout" })
    ]
  end

  let(:generic_deployment_metrics) do
    [
      build_metric("github.deployment.some_metric", "workflow1", "deploy-prod", "success", 120),
      build_metric("some.deployment.metric", "workflow2", "deploy-dev", "success", 150)
    ]
  end

  # Mock multi-repository metrics
  let(:multi_repo_metrics) do
    [
      # First repository
      build_metric("github.ci.deploy.duration", "workflow1", "deploy-prod", "success", 120, 120, repository),
      build_metric("github.ci.deploy.duration", "workflow2", "deploy-prod", "failure", 90, 150, repository),
      # Second repository
      build_metric("github.ci.deploy.duration", "workflow3", "deploy-prod", "success", 150, 100, "other/repo"),
      build_metric("github.ci.deploy.duration", "workflow4", "deploy-prod", "success", 180, 90, "other/repo")
    ]
  end

  before do
    # Mock DependencyContainer for metric_naming_port
    allow(DependencyContainer).to receive(:resolve).with(:metric_naming_port).and_return(metric_naming_port)
  end

  describe "#call" do
    context "when not using cache" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        # Setup the storage_port to return our test metrics
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.duration",
          start_time: anything
        ).and_return(deploy_duration_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment.duration",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.completed",
          start_time: anything
        ).and_return(success_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment_status.success",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.failed",
          start_time: anything
        ).and_return(failure_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment_status.failure",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment_frequency",
          start_time: anything
        ).and_return(deploy_frequency_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment.created",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.change_failure_rate",
          start_time: anything
        ).and_return(change_failure_rate_metrics)

        allow(storage_port).to receive(:list_metrics_with_name_pattern).with(
          "%deploy%",
          start_time: anything
        ).and_return([])
      end

      it "returns deployment performance metrics" do
        result = use_case.call(time_period: time_period)

        expect(result).to include(
          total: 4,
          success_rate: 75.0,
          avg_duration: 102.5
        )
      end

      it "includes time series data" do
        result = use_case.call(time_period: time_period)

        expect(result[:deploys_by_day]).to be_a(Hash)
        expect(result[:success_rate_by_day]).to be_a(Hash)
      end

      it "includes workflow-specific metrics" do
        result = use_case.call(time_period: time_period)

        expect(result[:deploys_by_workflow]).to include("workflow1" => 2, "workflow2" => 2)
      end

      it "calculates deployment frequency" do
        result = use_case.call(time_period: time_period)

        expect(result[:deployment_frequency]).to be_a(Float)
        # 4 deploys over 30 days = 0.133... deploys per day
        expect(result[:deployment_frequency]).to be_within(0.05).of(0.13)
      end

      it "categorizes deployment durations by environment" do
        result = use_case.call(time_period: time_period)

        expect(result[:durations_by_environment]).to be_a(Hash)
        expect(result[:durations_by_environment]).to have_key("production")
      end

      it "identifies common failure reasons" do
        result = use_case.call(time_period: time_period)

        expect(result[:common_failure_reasons]).to be_a(Hash)
        expect(result[:common_failure_reasons]).to include("timeout" => 1)
      end
    end

    context "when using fallback metrics" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        # Primary metrics return empty
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.duration",
          start_time: anything
        ).and_return([])

        # Fallback metrics return data
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment.duration",
          start_time: anything
        ).and_return(deployment_duration_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.completed",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment_status.success",
          start_time: anything
        ).and_return(deployment_status_success_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.failed",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment_status.failure",
          start_time: anything
        ).and_return(deployment_status_failure_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment_frequency",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment.created",
          start_time: anything
        ).and_return(deployment_created_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.change_failure_rate",
          start_time: anything
        ).and_return([])

        # Don't need generic pattern fallback in this test
        allow(storage_port).to receive(:list_metrics_with_name_pattern).with(
          "%deploy%",
          start_time: anything
        ).and_return([])
      end

      it "uses fallback metrics when primary ones are not available" do
        result = use_case.call(time_period: time_period)

        expect(result[:total]).to eq(2) # 1 success + 1 failure
        expect(result[:avg_duration]).to eq(100) # Value from deployment_duration_metrics
      end
    end

    context "when using generic fallback metrics" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        # All specific metrics return empty
        allow(storage_port).to receive(:list_metrics).with(any_args).and_return([])

        # Generic pattern search returns data
        allow(storage_port).to receive(:list_metrics_with_name_pattern).with(
          "%deploy%",
          start_time: anything
        ).and_return(generic_deployment_metrics)
      end

      it "falls back to generic metrics when specific ones are not available" do
        result = use_case.call(time_period: time_period)

        expect(result[:total]).to eq(2) # Both generic metrics counted as successes
        expect(result[:deploys_by_workflow]).to include("workflow1" => 1, "workflow2" => 1)
      end
    end

    context "when filtering by repository" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        # Set success and failure metrics for both repositories
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.completed",
          start_time: anything
        ).and_return([
                       build_metric("github.ci.deploy.completed", "workflow1", "deploy-prod", "success", 120, 1,
                                    repository),
                       build_metric("github.ci.deploy.completed", "workflow3", "deploy-prod", "success", 120, 1,
                                    "other/repo")
                     ])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.failed",
          start_time: anything
        ).and_return([
                       build_metric("github.ci.deploy.failed", "workflow2", "deploy-prod", "failure", 90, 1,
                                    repository),
                       build_metric("github.ci.deploy.failed", "workflow4", "deploy-prod", "failure", 90, 1,
                                    "other/repo")
                     ])

        # Set multi-repo metrics for durations
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.duration",
          start_time: anything
        ).and_return(multi_repo_metrics)

        # Default empty for other metrics
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment.duration",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment_status.success",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment_status.failure",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment_frequency",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment.created",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.change_failure_rate",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics_with_name_pattern).with(any_args).and_return([])
      end

      it "filters metrics by repository" do
        result = use_case.call(time_period: time_period, repository: repository)

        # Should only count metrics from the specified repository
        expect(result[:total]).to eq(2) # 1 success + 1 failure from the test/repo

        # Should have duration data from the filtered metrics
        expect(result[:durations_by_environment].values.any?).to be true
      end

      it "properly filters metrics across multiple repositories" do
        # First test with the main repository
        first_result = use_case.call(time_period: time_period, repository: repository)

        # Then test with a different repository
        second_result = use_case.call(time_period: time_period, repository: "other/repo")

        # The two sets of metrics should be different
        expect(first_result[:total]).to eq(2) # 1 success + 1 failure from test/repo
        expect(second_result[:total]).to eq(2) # 1 success + 1 failure from other/repo

        # The average durations should be different
        expect(first_result[:avg_duration]).not_to eq(second_result[:avg_duration])
      end
    end

    context "when no metrics are found" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        # All metrics return empty
        allow(storage_port).to receive(:list_metrics).with(any_args).and_return([])
        allow(storage_port).to receive(:list_metrics_with_name_pattern).with(any_args).and_return([])
      end

      it "returns zero values for all counts" do
        result = use_case.call(time_period: time_period)

        expect(result[:total]).to eq(0)
        expect(result[:success_rate]).to eq(0)
        expect(result[:avg_duration]).to eq(0)
        expect(result[:deployment_frequency]).to eq(0)
      end

      it "returns empty collections for all series data" do
        result = use_case.call(time_period: time_period)

        # Days should still be initialized but with zero values
        expect(result[:deploys_by_day].values.all?(&:zero?)).to be true
        expect(result[:deploys_by_workflow]).to be_empty
        expect(result[:durations_by_environment]).to be_empty
        expect(result[:common_failure_reasons]).to be_empty
      end
    end

    context "when using cache" do
      let(:cache_key) { "deployment_performance:days_30:repo_test_repo" }
      let(:cached_result) { { total: 10, success_rate: 90.0 }.to_json }

      before do
        allow(cache_port).to receive(:read).with(cache_key).and_return(cached_result)
        allow(storage_port).to receive(:list_metrics).with(any_args).and_return([])
        allow(storage_port).to receive(:list_metrics_with_name_pattern).with(any_args).and_return([])
      end

      it "returns cached results when available" do
        result = use_case.call(time_period: time_period, repository: repository)

        expect(result).to include(total: 10, success_rate: 90.0)
        expect(storage_port).not_to have_received(:list_metrics)
      end

      it "caches results when not in cache" do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

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

        # Allow cache writing since it will try to write the new results
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        result = use_case.call(time_period: time_period)

        # Should have attempted to read metrics since cache was invalid
        expect(storage_port).to have_received(:list_metrics).at_least(:once)
      end
    end
  end

  # Helper methods
  def build_metric(name, workflow_name, job_name, conclusion, timestamp_offset = 0, value = 1, repo = repository,
                   extra_dimensions = {})
    dimensions = {
      "repository" => repo,
      "workflow_name" => workflow_name,
      "job_name" => job_name,
      "conclusion" => conclusion,
      "environment" => if job_name.include?("prod")
                         "production"
                       else
                         (job_name.include?("staging") ? "staging" : "development")
                       end
    }

    # Ensure extra_dimensions are handled properly with string keys
    extra_dimensions.each do |k, v|
      dimensions[k.to_s] = v
    end

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
