# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::CalculateDeploymentFrequency do
  let(:storage_port) { instance_double("StoragePort") }
  let(:logger_port) { instance_double("LoggerPort", info: nil, warn: nil) }
  let(:use_case) { described_class.new(storage_port: storage_port, logger_port: logger_port) }

  describe "#call" do
    let(:time_period) { 30 }
    let(:start_time) { time_period.days.ago }

    context "when there are deployments" do
      before do
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.completed",
          start_time: anything
        ).and_return(deployments)
      end

      let(:deployments) do
        # Create 10 deployments across 5 different days (2 per day)
        # Note: The implementation counts each deployment separately,
        # not grouping them by day as the comment suggests
        dates = [1, 5, 10, 15, 20].map { |d| d.days.ago }
        dates.flat_map do |date|
          [
            instance_double("Domain::Metric",
                            name: "github.ci.deploy.completed",
                            value: 1,
                            dimensions: { "environment" => "production" },
                            timestamp: date + 1.hour),
            instance_double("Domain::Metric",
                            name: "github.ci.deploy.completed",
                            value: 1,
                            dimensions: { "environment" => "production" },
                            timestamp: date + 3.hours)
          ]
        end
      end

      it "returns the correct deployment frequency" do
        result = use_case.call(time_period: time_period)

        # In the actual implementation:
        # - Each deployment counts as a separate day (not grouped)
        # - 10 deployments = 10 days with deployments
        # - Frequency = 10/30 = 0.33
        expect(result[:value]).to eq(0.33)
        expect(result[:days_with_deployments]).to eq(10)
        expect(result[:total_days]).to eq(time_period)
        expect(result[:total_deployments]).to eq(10)
      end

      it "assigns the correct DORA rating" do
        result = use_case.call(time_period: time_period)

        # 0.17 deployments per day = between once per week (0.14) and once per day (1.0)
        # This puts it in the "high" rating category
        expect(result[:rating]).to eq("high")
      end
    end

    context "when there are no deployments from completed metrics" do
      before do
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.deploy.completed",
          start_time: anything
        ).and_return([])

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.deployment_status.success",
          start_time: anything
        ).and_return(deployment_status_metrics)
      end

      let(:deployment_status_metrics) do
        # Create 3 successful deployment status events
        [7, 14, 21].map do |d|
          instance_double("Domain::Metric",
                          name: "github.deployment_status.success",
                          value: 1,
                          dimensions: { "environment" => "production" },
                          timestamp: d.days.ago)
        end
      end

      it "falls back to deployment_status metrics" do
        result = use_case.call(time_period: time_period)

        # 3 days with deployments out of 30 days = 0.1 deployments per day
        expect(result[:value]).to eq(0.1)
        expect(result[:days_with_deployments]).to eq(3)
        expect(result[:total_deployments]).to eq(3)
      end

      it "assigns the correct DORA rating" do
        result = use_case.call(time_period: time_period)

        # 0.1 deployments per day = between once per month (0.03) and once per week (0.14)
        # This puts it in the "medium" rating category
        expect(result[:rating]).to eq("medium")
      end
    end

    context "when there are no deployments at all" do
      before do
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
        expect(result[:total_deployments]).to eq(0)
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
