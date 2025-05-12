# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::AnalyzeTeamPerformance do
  subject(:use_case) do
    described_class.new(
      issue_metric_repository: issue_metric_repository,
      storage_port: storage_port,
      cache_port: cache_port,
      logger_port: logger_port
    )
  end

  let(:issue_metric_repository) { instance_double("Repositories::IssueMetricRepository") }
  let(:storage_port) { instance_double("Ports::StoragePort") }
  let(:cache_port) { instance_double("Ports::CachePort") }
  let(:logger_port) { instance_double("Logger", debug: nil, error: nil) }

  describe "#calculate_team_velocity" do
    let(:since_date) { 30.days.ago }
    let(:until_date) { Time.current }
    let(:mock_close_rates) do
      [
        {
          start_time: 4.weeks.ago,
          end_time: 3.weeks.ago,
          count: 5,
          source_breakdown: { "github" => 3, "jira" => 2 }
        },
        {
          start_time: 3.weeks.ago,
          end_time: 2.weeks.ago,
          count: 8,
          source_breakdown: { "github" => 5, "jira" => 3 }
        },
        {
          start_time: 2.weeks.ago,
          end_time: 1.week.ago,
          count: 7,
          source_breakdown: { "github" => 4, "jira" => 3 }
        },
        {
          start_time: 1.week.ago,
          end_time: Time.current,
          count: 10,
          source_breakdown: { "github" => 6, "jira" => 4 }
        }
      ]
    end

    let(:mock_backlog_growth) do
      [
        {
          start_time: 4.weeks.ago,
          end_time: 3.weeks.ago,
          created: 7,
          closed: 5,
          net_change: 2
        },
        {
          start_time: 3.weeks.ago,
          end_time: 2.weeks.ago,
          created: 10,
          closed: 8,
          net_change: 2
        },
        {
          start_time: 2.weeks.ago,
          end_time: 1.week.ago,
          created: 9,
          closed: 7,
          net_change: 2
        },
        {
          start_time: 1.week.ago,
          end_time: Time.current,
          created: 12,
          closed: 10,
          net_change: 2
        }
      ]
    end

    before do
      allow(issue_metric_repository).to receive(:issue_close_rates).and_return(mock_close_rates)
      allow(issue_metric_repository).to receive(:backlog_growth).and_return(mock_backlog_growth)

      # No cache initially
      allow(cache_port).to receive(:read).and_return(nil)
      allow(cache_port).to receive(:write).and_return(true)
    end

    it "calculates team velocity correctly" do
      result = use_case.calculate_team_velocity(since: since_date, until_time: until_date)

      expect(result[:team_velocity]).to be_within(0.1).of(7.5) # (5+8+7+10) / 4 = 7.5
      expect(result[:weekly_velocities].size).to eq(4)
      expect(result[:total_closed]).to eq(30) # 5+8+7+10 = 30
      expect(result[:total_created]).to eq(38) # 7+10+9+12 = 38
      expect(result[:completion_rate]).to be_within(0.1).of(78.9) # (30/38) * 100 ≈ 78.9%
      expect(result[:backlog_growth]).to eq(8) # 2+2+2+2 = 8
    end

    it "uses cached data when available" do
      cached_data = { team_velocity: 7.5, weekly_velocities: [], total_closed: 30 }
      allow(cache_port).to receive(:read).and_return(cached_data)

      result = use_case.calculate_team_velocity(since: since_date, until_time: until_date)

      expect(result).to eq(cached_data)
      expect(issue_metric_repository).not_to have_received(:issue_close_rates)
    end

    it "handles errors gracefully" do
      allow(issue_metric_repository).to receive(:issue_close_rates).and_raise(StandardError, "Connection error")

      result = use_case.calculate_team_velocity(since: since_date, until_time: until_date)

      expect(result[:team_velocity]).to eq(0)
      expect(result[:weekly_velocities]).to eq([])
      expect(logger_port).to have_received(:error)
    end
  end

  describe "#analyze_performance_trends" do
    let(:since_date) { 30.days.ago }
    let(:velocity_data) do
      {
        team_velocity: 7.5,
        weekly_velocities: [
          { count: 5, week_starting: 4.weeks.ago },
          { count: 6, week_starting: 3.weeks.ago },
          { count: 8, week_starting: 2.weeks.ago },
          { count: 9, week_starting: 1.week.ago }
        ],
        total_closed: 28,
        total_created: 35,
        completion_rate: 80.0,
        num_weeks: 4,
        backlog_growth: 7
      }
    end

    let(:resolution_stats) do
      {
        issue_count: 28,
        average_hours: 24.5,
        median_hours: 18.2,
        p90_hours: 48.3
      }
    end

    let(:issue_types) do
      [
        { type: "bug", count: 12, sources: { "github" => 7, "jira" => 5 } },
        { type: "feature", count: 10, sources: { "github" => 6, "jira" => 4 } },
        { type: "enhancement", count: 6, sources: { "github" => 4, "jira" => 2 } }
      ]
    end

    let(:issue_priorities) do
      [
        { priority: "high", count: 8, sources: { "github" => 5, "jira" => 3 } },
        { priority: "medium", count: 15, sources: { "github" => 9, "jira" => 6 } },
        { priority: "low", count: 5, sources: { "github" => 3, "jira" => 2 } }
      ]
    end

    let(:assignee_workload) do
      [
        { assignee: "developer1", issue_count: 5, source: "github" },
        { assignee: "developer2", issue_count: 4, source: "github" },
        { assignee: "developer3", issue_count: 3, source: "jira" }
      ]
    end

    before do
      allow(use_case).to receive(:calculate_team_velocity).and_return(velocity_data)
      allow(issue_metric_repository).to receive(:resolution_time_stats).and_return(resolution_stats)
      allow(issue_metric_repository).to receive(:issue_type_distribution).and_return(issue_types)
      allow(issue_metric_repository).to receive(:issue_priority_distribution).and_return(issue_priorities)
      allow(issue_metric_repository).to receive(:assignee_workload).and_return(assignee_workload)

      # No cache initially
      allow(cache_port).to receive(:read).and_return(nil)
      allow(cache_port).to receive(:write).and_return(true)
    end

    it "calculates performance trends correctly" do
      result = use_case.analyze_performance_trends(since: since_date)

      expect(result[:velocity_trend_percentage]).to be_within(0.1).of(50.0) # (8.5-5.5)/5.5*100 ≈ 54.5%
      expect(result[:avg_resolution_time]).to eq(24.5)
      expect(result[:median_resolution_time]).to eq(18.2)
      expect(result[:issue_count]).to eq(28)
      expect(result[:issue_types].size).to eq(3)
      expect(result[:issue_priorities].size).to eq(3)
      expect(result[:top_assignees].size).to eq(3)
    end

    it "handles errors gracefully" do
      allow(use_case).to receive(:calculate_team_velocity).and_raise(StandardError, "Error in calculation")

      result = use_case.analyze_performance_trends(since: since_date)

      expect(result[:velocity_trend_percentage]).to eq(0)
      expect(result[:avg_resolution_time]).to eq(0)
      expect(logger_port).to have_received(:error)
    end
  end

  describe "#get_team_performance_metrics" do
    let(:time_period) { 30 }
    let(:velocity_data) do
      {
        team_velocity: 7.5,
        weekly_velocities: [{ count: 5 }, { count: 10 }],
        total_closed: 30,
        total_created: 38,
        completion_rate: 78.9,
        backlog_growth: 8
      }
    end

    let(:trends_data) do
      {
        velocity_trend_percentage: 20.0,
        avg_resolution_time: 24.5,
        median_resolution_time: 18.2,
        issue_count: 28,
        issue_types: [{ type: "bug", count: 12 }],
        issue_priorities: [{ priority: "high", count: 8 }],
        top_assignees: [{ assignee: "dev1", issue_count: 5 }]
      }
    end

    before do
      allow(use_case).to receive(:calculate_team_velocity).and_return(velocity_data)
      allow(use_case).to receive(:analyze_performance_trends).and_return(trends_data)
    end

    it "combines velocity and trends data correctly" do
      result = use_case.get_team_performance_metrics(time_period: time_period)

      expect(result[:team_velocity]).to eq(7.5)
      expect(result[:weekly_velocities]).to eq([{ count: 5 }, { count: 10 }])
      expect(result[:total_closed]).to eq(30)
      expect(result[:total_created]).to eq(38)
      expect(result[:completion_rate]).to eq(78.9)
      expect(result[:velocity_trend]).to eq(20.0)
      expect(result[:avg_resolution_time]).to eq(24.5)
      expect(result[:median_resolution_time]).to eq(18.2)
      expect(result[:issue_types]).to eq([{ type: "bug", count: 12 }])
      expect(result[:issue_priorities]).to eq([{ priority: "high", count: 8 }])
      expect(result[:top_assignees]).to eq([{ assignee: "dev1", issue_count: 5 }])
      expect(result[:backlog_growth]).to eq(8)
    end
  end
end
