# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::CalculateDeploymentFrequency do
  let(:storage_port) { instance_double("StoragePort") }
  let(:logger_port) { instance_double("LoggerPort").as_null_object }
  let(:use_case) { described_class.new(storage_port: storage_port, logger_port: logger_port) }

  describe "#call" do
    let(:time_period) { 30 }
    let(:start_time) { time_period.days.ago }

    context "when there are deployments" do
      before do
        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment_frequency",
          start_time: anything
        ).and_return(deployment_metrics)

        # Add fallback mocks for other metric types that might be checked
        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment_frequency.hourly",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment_frequency.5min",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.completed",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment_status.success",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment.total",
          start_time: anything
        ).and_return([])
      end

      let(:deployment_metrics) do
        # Create 30 deployment metrics (one per day) over the 30-day period
        (1..30).map do |days_ago|
          instance_double("Domain::Metric",
                          name: "dora.deployment_frequency",
                          value: 1.0,
                          dimensions: {},
                          timestamp: days_ago.days.ago)
        end
      end

      it "returns the correct deployment frequency" do
        result = use_case.call(time_period: time_period)

        # 30 deployments over 30 days = 1 per day
        expect(result[:value]).to eq(1.0)
        expect(result[:days_with_deployments]).to eq(30)
        expect(result[:total_days]).to eq(30)
      end

      it "assigns the correct DORA rating" do
        result = use_case.call(time_period: time_period)

        # 1.0 deployments per day gets "elite" rating
        expect(result[:rating]).to eq("elite")
      end
    end

    context "when there are no deployments from completed metrics" do
      before do
        # Return empty array for dora.deployment_frequency
        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment_frequency",
          start_time: anything
        ).and_return([])

        # Return empty array for hourly metrics
        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment_frequency.hourly",
          start_time: anything
        ).and_return([])

        # Return empty array for 5min metrics
        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment_frequency.5min",
          start_time: anything
        ).and_return([])

        # Return empty array for github.ci.deploy.completed
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.completed",
          start_time: anything
        ).and_return([])

        # Return deployment_status metrics for fallback
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment_status.success",
          start_time: anything
        ).and_return(deployment_status_metrics)

        # Add fallback mock for the last metric type
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment.total",
          start_time: anything
        ).and_return([])
      end

      let(:deployment_status_metrics) do
        # Create 10 deployment metrics over the 30-day period
        (1..10).map do |days_ago|
          instance_double("Domain::Metric",
                          name: "github.deployment_status.success",
                          value: 1.0,
                          dimensions: {},
                          timestamp: (days_ago * 3).days.ago) # Every 3 days
        end
      end

      it "falls back to deployment_status metrics" do
        result = use_case.call(time_period: time_period)

        # 10 deployments over 30 days = 0.33 per day
        expect(result[:value]).to be_within(0.01).of(0.33)
        expect(result[:days_with_deployments]).to eq(10)
        expect(result[:total_days]).to eq(30)
      end

      it "assigns the correct DORA rating" do
        result = use_case.call(time_period: time_period)

        # 0.33 deployments per day gets "high" rating (between daily and weekly)
        expect(result[:rating]).to eq("high")
      end
    end

    context "when there are no deployments at all" do
      before do
        # Return empty arrays for all metric queries
        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment_frequency",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment_frequency.hourly",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "dora.deployment_frequency.5min",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.completed",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment_status.success",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment.total",
          start_time: anything
        ).and_return([])
      end

      it "returns zero frequency" do
        result = use_case.call(time_period: time_period)

        expect(result[:value]).to eq(0)
        expect(result[:days_with_deployments]).to eq(0)
        expect(result[:total_days]).to eq(30)
      end

      it "assigns a 'low' DORA rating" do
        result = use_case.call(time_period: time_period)

        expect(result[:rating]).to eq("low")
      end
    end
  end

  describe "#determine_rating" do
    it "returns 'elite' rating for daily deployments" do
      allow(use_case).to receive(:determine_rating).and_call_original
      expect(use_case.send(:determine_rating, 1.0)).to eq("elite")
      expect(use_case.send(:determine_rating, 2.5)).to eq("elite")
    end

    it "returns 'high' rating for weekly deployments" do
      allow(use_case).to receive(:determine_rating).and_call_original
      expect(use_case.send(:determine_rating, 0.2)).to eq("high")  # Once every 5 days
      expect(use_case.send(:determine_rating, 0.14)).to eq("high") # Once per week
    end

    it "returns 'medium' rating for monthly deployments" do
      allow(use_case).to receive(:determine_rating).and_call_original
      expect(use_case.send(:determine_rating, 0.1)).to eq("medium") # Once every 10 days
      expect(use_case.send(:determine_rating, 0.03)).to eq("medium") # Once per month
    end

    it "returns 'low' rating for less than monthly deployments" do
      allow(use_case).to receive(:determine_rating).and_call_original
      expect(use_case.send(:determine_rating, 0.02)).to eq("low") # Once every 50 days
      expect(use_case.send(:determine_rating, 0.0)).to eq("low")  # Never
    end
  end
end
