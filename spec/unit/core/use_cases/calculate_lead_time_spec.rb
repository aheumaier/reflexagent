# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::CalculateLeadTime do
  let(:storage_port) { instance_double("StoragePort") }
  let(:logger_port) { instance_double("LoggerPort", info: nil, warn: nil) }
  let(:use_case) { described_class.new(storage_port: storage_port, logger_port: logger_port) }

  describe "#call" do
    let(:time_period) { 30 }
    let(:start_time) { time_period.days.ago }

    context "when there are lead time metrics" do
      before do
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.lead_time",
          start_time: anything
        ).and_return(lead_time_metrics)
      end

      let(:lead_time_metrics) do
        # Create metrics with different lead times (in seconds)
        # 1 hour (3600s), 5 hours (18000s), 24 hours (86400s), 48 hours (172800s), 120 hours (432000s)
        [3600, 18_000, 86_400, 172_800, 432_000].map do |seconds|
          instance_double("Domain::Metric",
                          name: "github.ci.lead_time",
                          value: seconds,
                          dimensions: { "environment" => "production" },
                          timestamp: rand(1..20).days.ago)
        end
      end

      it "calculates the average lead time in hours" do
        result = use_case.call(time_period: time_period)

        # Average = (3600 + 18000 + 86400 + 172800 + 432000) / 5 / 3600 = 39.6 hours
        expect(result[:value]).to be_within(0.1).of(39.6)
        expect(result[:sample_size]).to eq(5)
      end

      it "assigns the correct DORA rating" do
        result = use_case.call(time_period: time_period)

        # 39.6 hours = between one day (24h) and one week (168h)
        # This puts it in the "high" rating category
        expect(result[:rating]).to eq("high")
      end

      it "calculates the median (50th percentile) correctly" do
        result = use_case.call(time_period: time_period, percentile: 50)

        # Sorted values in hours: [1, 5, 24, 48, 120]
        # Median = 24 hours
        expect(result[:percentile][:value]).to be_within(0.1).of(24.0)
        expect(result[:percentile][:percentile]).to eq(50)
      end

      it "calculates the 75th percentile correctly" do
        result = use_case.call(time_period: time_period, percentile: 75)

        # Sorted values in hours: [1, 5, 24, 48, 120]
        # 75th percentile = value at index 3 (zero-based) = 48 hours
        expect(result[:percentile][:value]).to be_within(0.1).of(48.0)
        expect(result[:percentile][:percentile]).to eq(75)
      end

      it "calculates the 95th percentile correctly" do
        result = use_case.call(time_period: time_period, percentile: 95)

        # Sorted values in hours: [1, 5, 24, 48, 120]
        # 95th percentile = value at index 4 (zero-based) = 120 hours
        expect(result[:percentile][:value]).to be_within(0.1).of(120.0)
        expect(result[:percentile][:percentile]).to eq(95)
      end
    end

    context "when there are very fast lead times" do
      before do
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.lead_time",
          start_time: anything
        ).and_return(fast_lead_time_metrics)
      end

      let(:fast_lead_time_metrics) do
        # Create metrics with fast lead times (in seconds)
        # 15 minutes (900s), 30 minutes (1800s), 45 minutes (2700s)
        [900, 1800, 2700].map do |seconds|
          instance_double("Domain::Metric",
                          name: "github.ci.lead_time",
                          value: seconds,
                          dimensions: { "environment" => "production" },
                          timestamp: rand(1..20).days.ago)
        end
      end

      it "calculates the average lead time in hours" do
        result = use_case.call(time_period: time_period)

        # Average = (900 + 1800 + 2700) / 3 / 3600 = 0.5 hours
        expect(result[:value]).to be_within(0.1).of(0.5)
      end

      it "assigns an 'elite' DORA rating" do
        result = use_case.call(time_period: time_period)

        # 0.5 hours is much less than 24 hours (one day)
        # This puts it in the "elite" rating category
        expect(result[:rating]).to eq("elite")
      end
    end

    context "when there are very slow lead times" do
      before do
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.lead_time",
          start_time: anything
        ).and_return(slow_lead_time_metrics)
      end

      let(:slow_lead_time_metrics) do
        # Create metrics with slow lead times (in seconds)
        # 2 weeks (1209600s), 3 weeks (1814400s), 5 weeks (3024000s)
        [1_209_600, 1_814_400, 3_024_000].map do |seconds|
          instance_double("Domain::Metric",
                          name: "github.ci.lead_time",
                          value: seconds,
                          dimensions: { "environment" => "production" },
                          timestamp: rand(1..20).days.ago)
        end
      end

      it "calculates the average lead time in hours" do
        result = use_case.call(time_period: time_period)

        # Average = (1209600 + 1814400 + 3024000) / 3 / 3600 = 560 hours
        expect(result[:value]).to be_within(1).of(560)
      end

      it "assigns a 'medium' DORA rating" do
        result = use_case.call(time_period: time_period)

        # 560 hours is between one week (168h) and one month (730h)
        # This puts it in the "medium" rating category
        expect(result[:rating]).to eq("medium")
      end
    end

    context "when there are extremely slow lead times" do
      before do
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.lead_time",
          start_time: anything
        ).and_return(extremely_slow_lead_time_metrics)
      end

      let(:extremely_slow_lead_time_metrics) do
        # Create metrics with extremely slow lead times (in seconds)
        # 6 weeks (3628800s), 8 weeks (4838400s)
        [3_628_800, 4_838_400].map do |seconds|
          instance_double("Domain::Metric",
                          name: "github.ci.lead_time",
                          value: seconds,
                          dimensions: { "environment" => "production" },
                          timestamp: rand(1..20).days.ago)
        end
      end

      it "calculates the average lead time in hours" do
        result = use_case.call(time_period: time_period)

        # Average = (3628800 + 4838400) / 2 / 3600 = 1176 hours
        expect(result[:value]).to be_within(1).of(1176)
      end

      it "assigns a 'low' DORA rating" do
        result = use_case.call(time_period: time_period)

        # 1176 hours is more than one month (730h)
        # This puts it in the "low" rating category
        expect(result[:rating]).to eq("low")
      end
    end

    context "when metrics include process breakdown information" do
      before do
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.lead_time",
          start_time: anything
        ).and_return(metrics_with_breakdown)
      end

      let(:metrics_with_breakdown) do
        [
          instance_double("Domain::Metric",
                          name: "github.ci.lead_time",
                          value: 90_000, # 25 hours
                          dimensions: {
                            "environment" => "production",
                            "code_review_hours" => "8.0",
                            "ci_hours" => "1.0",
                            "qa_hours" => "10.0",
                            "approval_hours" => "4.0",
                            "deployment_hours" => "2.0"
                          },
                          timestamp: 5.days.ago),
          instance_double("Domain::Metric",
                          name: "github.ci.lead_time",
                          value: 72_000, # 20 hours
                          dimensions: {
                            "environment" => "production",
                            "code_review_hours" => "6.0",
                            "ci_hours" => "0.5",
                            "qa_hours" => "8.0",
                            "approval_hours" => "3.5",
                            "deployment_hours" => "2.0"
                          },
                          timestamp: 3.days.ago)
        ]
      end

      it "returns process breakdown information when requested" do
        result = use_case.call(time_period: time_period, breakdown: true)

        expect(result[:breakdown]).to be_a(Hash)
        expect(result[:breakdown][:code_review]).to be_within(0.1).of(7.0)
        expect(result[:breakdown][:ci_pipeline]).to be_within(0.1).of(0.75)
        expect(result[:breakdown][:qa]).to be_within(0.1).of(9.0)
        expect(result[:breakdown][:approval]).to be_within(0.1).of(3.75)
        expect(result[:breakdown][:deployment]).to be_within(0.1).of(2.0)
        expect(result[:breakdown][:total]).to be_within(0.1).of(22.5)
      end
    end

    context "when there are no lead time metrics" do
      before do
        allow(storage_port).to receive(:list_metrics).with(
          name: "github.ci.lead_time",
          start_time: anything
        ).and_return([])
      end

      it "returns zero value" do
        result = use_case.call(time_period: time_period)

        expect(result[:value]).to eq(0)
        expect(result[:sample_size]).to eq(0)
      end

      it "assigns an 'unknown' DORA rating" do
        result = use_case.call(time_period: time_period)

        expect(result[:rating]).to eq("unknown")
      end
    end
  end

  describe "#determine_rating" do
    it "returns 'elite' rating for lead times less than 24 hours" do
      allow(use_case).to receive(:determine_rating).and_call_original
      expect(use_case.send(:determine_rating, 0.5)).to eq("elite")
      expect(use_case.send(:determine_rating, 23.9)).to eq("elite")
    end

    it "returns 'high' rating for lead times between 24 hours and one week" do
      allow(use_case).to receive(:determine_rating).and_call_original
      expect(use_case.send(:determine_rating, 24)).to eq("high")
      expect(use_case.send(:determine_rating, 167.9)).to eq("high")
    end

    it "returns 'medium' rating for lead times between one week and one month" do
      allow(use_case).to receive(:determine_rating).and_call_original
      expect(use_case.send(:determine_rating, 168)).to eq("medium")
      expect(use_case.send(:determine_rating, 729.9)).to eq("medium")
    end

    it "returns 'low' rating for lead times greater than one month" do
      allow(use_case).to receive(:determine_rating).and_call_original
      expect(use_case.send(:determine_rating, 730)).to eq("low")
      expect(use_case.send(:determine_rating, 1000)).to eq("low")
    end
  end

  describe "#calculate_percentile" do
    it "returns nil for invalid percentile values" do
      allow(use_case).to receive(:calculate_percentile).and_call_original
      expect(use_case.send(:calculate_percentile, [1, 2, 3], nil)).to be_nil
      expect(use_case.send(:calculate_percentile, [1, 2, 3], 25)).to be_nil
      expect(use_case.send(:calculate_percentile, [1, 2, 3], 99)).to be_nil
    end

    it "calculates percentiles correctly for various data sets" do
      allow(use_case).to receive(:calculate_percentile).and_call_original

      # Even number of elements
      expect(use_case.send(:calculate_percentile, [10, 30, 50, 70, 90, 100], 50)).to eq(60)

      # Odd number of elements
      expect(use_case.send(:calculate_percentile, [10, 30, 50, 70, 90], 50)).to eq(50)

      # 75th percentile
      expect(use_case.send(:calculate_percentile, [10, 30, 50, 70, 90], 75)).to eq(80)

      # 95th percentile
      expect(use_case.send(:calculate_percentile, [10, 30, 50, 70, 90, 100, 120, 140, 160, 180, 200], 95)).to eq(190)
    end
  end
end
