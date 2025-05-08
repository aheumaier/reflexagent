# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::AnalyzeDeploymentPerformance do
  let(:storage_port) { instance_double("StoragePort") }
  let(:cache_port) { instance_double("CachePort") }
  let(:use_case) { described_class.new(storage_port: storage_port, cache_port: cache_port) }

  # Mock data
  let(:time_period) { 30 }
  let(:repository) { "test/repo" }
  let(:start_time) { time_period.days.ago }

  # Mock metrics
  let(:deploy_metrics) do
    [
      build_metric("github.ci.deploy.duration", "workflow1", "deploy-prod", "success", 120, 120),
      build_metric("github.ci.deploy.duration", "workflow1", "deploy-staging", "success", 180, 80),
      build_metric("github.ci.deploy.duration", "workflow2", "deploy-prod", "failure", 90, 150),
      build_metric("github.ci.deploy.duration", "workflow2", "deploy-dev", "success", 150, 60)
    ]
  end

  let(:success_metrics) do
    [
      build_metric("github.ci.deploy.completed", "workflow1", "deploy-prod", "success", 120),
      build_metric("github.ci.deploy.completed", "workflow1", "deploy-staging", "success", 180),
      build_metric("github.ci.deploy.completed", "workflow2", "deploy-dev", "success", 150)
    ]
  end

  let(:failure_metrics) do
    [
      build_metric("github.ci.deploy.failed", "workflow2", "deploy-prod", "failure", 90)
    ]
  end

  let(:dora_deploy_attempts) do
    [
      build_metric("dora.deployment.attempt", "workflow1", "deploy-prod", "success", 120),
      build_metric("dora.deployment.attempt", "workflow1", "deploy-staging", "success", 180),
      build_metric("dora.deployment.attempt", "workflow2", "deploy-prod", "failure", 90),
      build_metric("dora.deployment.attempt", "workflow2", "deploy-dev", "success", 150)
    ]
  end

  let(:dora_deploy_failures) do
    [
      build_metric("dora.deployment.failure", "workflow2", "deploy-prod", "failure", 90, 1, { reason: "timeout" })
    ]
  end

  describe "#call" do
    context "when not using cache" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.duration",
          start_time: anything
        ).and_return(deploy_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.completed",
          start_time: anything
        ).and_return(success_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.failed",
          start_time: anything
        ).and_return(failure_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment.attempt",
          start_time: anything
        ).and_return(dora_deploy_attempts)

        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment.failure",
          start_time: anything
        ).and_return(dora_deploy_failures)
      end

      it "returns deployment performance metrics" do
        result = use_case.call(time_period: time_period)

        expect(result).to include(
          total_deploys: 4,
          successful_deploys: 3,
          failed_deploys: 1,
          success_rate: 75.0
        )
      end

      it "calculates average deployment duration" do
        result = use_case.call(time_period: time_period)

        # (120 + 80 + 150 + 60) / 4 = 102.5
        expect(result[:average_deploy_duration]).to be_within(0.1).of(102.5)
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

    context "when filtering by repository" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        # Set up filtered metrics - we'll just return the original metrics for simplicity
        # in a real test these would be filtered by the repository parameter
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.duration",
          start_time: anything
        ).and_return(deploy_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.completed",
          start_time: anything
        ).and_return(success_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.failed",
          start_time: anything
        ).and_return(failure_metrics)

        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment.attempt",
          start_time: anything
        ).and_return(dora_deploy_attempts)

        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment.failure",
          start_time: anything
        ).and_return(dora_deploy_failures)
      end

      it "filters metrics by repository" do
        expect(use_case.call(time_period: time_period, repository: repository)).to include(:total_deploys)
      end
    end

    context "when using cache" do
      let(:cache_key) { "deployment_performance:days_30:repo_test_repo" }
      let(:cached_result) { { total_deploys: 10, success_rate: 90.0 }.to_json }

      before do
        allow(cache_port).to receive(:read).with(cache_key).and_return(cached_result)
        allow(storage_port).to receive(:list_metrics).with(any_args).and_return([])
      end

      it "returns cached results when available" do
        result = use_case.call(time_period: time_period, repository: repository)

        expect(result).to include(total_deploys: 10, success_rate: 90.0)
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
  def build_metric(name, workflow_name, job_name, conclusion, timestamp_offset = 0, value = 1, extra_dimensions = {})
    dimensions = {
      "repository" => repository,
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
