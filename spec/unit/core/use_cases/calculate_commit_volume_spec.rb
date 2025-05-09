# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::CalculateCommitVolume do
  let(:storage_port) { instance_double("StoragePort") }
  let(:cache_port) { instance_double("CachePort") }
  let(:use_case) { described_class.new(storage_port: storage_port, cache_port: cache_port) }

  describe "#call" do
    let(:time_period) { 30 }
    let(:repository) { "test/repo" }
    let(:start_time) { time_period.days.ago }

    context "when there are commit metrics" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.push.commits.total",
          start_time: anything
        ).and_return(commit_metrics)
      end

      let(:commit_metrics) do
        # Create 10 commit metrics spread across 5 days
        # Ensure the dates are at noon to avoid midnight crossing issues
        dates = [1, 5, 10, 15, 20].map { |d| d.days.ago.noon }

        dates.flat_map do |date|
          [
            instance_double("Domain::Metric",
                            name: "github.push.commits.total",
                            value: 3,
                            dimensions: { "repository" => repository },
                            timestamp: date), # First metric at noon
            instance_double("Domain::Metric",
                            name: "github.push.commits.total",
                            value: 2,
                            dimensions: { "repository" => repository },
                            timestamp: date + 1.hour) # Second metric 1 hour later (still same day)
          ]
        end
      end

      it "calculates the correct total commits" do
        result = use_case.call(time_period: time_period, repository: repository)

        # Each date has metrics with values 3 and 2, so 5 commits per day over 5 days = 25
        expect(result[:total_commits]).to eq(25)
      end

      it "calculates the correct days with commits" do
        result = use_case.call(time_period: time_period, repository: repository)

        # We have metrics for 5 different days
        expect(result[:days_with_commits]).to eq(5)
      end

      it "calculates the correct commits per day" do
        result = use_case.call(time_period: time_period, repository: repository)

        # 25 commits over 30 days = 0.83 commits per day
        expect(result[:commits_per_day]).to eq(0.83)
      end

      it "calculates the correct commit frequency" do
        result = use_case.call(time_period: time_period, repository: repository)

        # 5 days with commits out of 30 days = 0.17 frequency
        expect(result[:commit_frequency]).to eq(0.17)
      end

      it "includes daily activity data" do
        result = use_case.call(time_period: time_period, repository: repository)

        expect(result[:daily_activity]).to be_an(Array)
        expect(result[:daily_activity].size).to eq(5)

        # Each day should have a date and count
        first_day = result[:daily_activity].first
        expect(first_day).to include(:date, :count)
        expect(first_day[:count]).to eq(5) # 3 + 2 = 5 commits
      end

      it "caches the result" do
        expect(cache_port).to receive(:write).with(
          "commit_volume:test/repo:days_30",
          anything,
          expires_in: 1.hour
        )

        use_case.call(time_period: time_period, repository: repository)
      end
    end

    context "when filtering by repository" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.push.commits.total",
          start_time: anything
        ).and_return(mixed_repo_metrics)
      end

      let(:mixed_repo_metrics) do
        [
          instance_double("Domain::Metric",
                          name: "github.push.commits.total",
                          value: 3,
                          dimensions: { "repository" => repository },
                          timestamp: 1.day.ago),
          instance_double("Domain::Metric",
                          name: "github.push.commits.total",
                          value: 5,
                          dimensions: { "repository" => "other/repo" },
                          timestamp: 2.days.ago)
        ]
      end

      it "only counts metrics for the specified repository" do
        result = use_case.call(time_period: time_period, repository: repository)

        # Only 3 commits from the test/repo repository
        expect(result[:total_commits]).to eq(3)
        expect(result[:days_with_commits]).to eq(1)
      end
    end

    context "when there are no metrics" do
      before do
        allow(cache_port).to receive(:read).with(anything).and_return(nil)
        allow(cache_port).to receive(:write).with(anything, anything, expires_in: anything)

        allow(storage_port).to receive(:list_metrics).with(
          name: "github.push.commits.total",
          start_time: anything
        ).and_return([])
      end

      it "returns zeros for all metrics" do
        result = use_case.call(time_period: time_period)

        expect(result[:total_commits]).to eq(0)
        expect(result[:days_with_commits]).to eq(0)
        expect(result[:commits_per_day]).to eq(0)
        expect(result[:commit_frequency]).to eq(0)
        expect(result[:daily_activity]).to eq([])
      end
    end

    context "when retrieving from cache" do
      let(:cached_result) do
        {
          total_commits: 42,
          days_with_commits: 7,
          days_analyzed: time_period,
          commits_per_day: 1.4,
          commit_frequency: 0.23,
          daily_activity: [
            { date: "2023-01-01", count: 5 },
            { date: "2023-01-02", count: 7 }
          ]
        }.to_json
      end

      before do
        allow(cache_port).to receive(:read).with("commit_volume:test/repo:days_30").and_return(cached_result)
      end

      it "returns the cached result" do
        result = use_case.call(time_period: time_period, repository: repository)

        # Should match our cached values
        expect(result[:total_commits]).to eq(42)
        expect(result[:days_with_commits]).to eq(7)
        expect(result[:commits_per_day]).to eq(1.4)
        expect(result[:daily_activity].size).to eq(2)
      end

      it "doesn't call the storage port" do
        expect(storage_port).not_to receive(:list_metrics)

        use_case.call(time_period: time_period, repository: repository)
      end
    end
  end
end
