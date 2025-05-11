# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repositories::IssueMetricRepository do
  let(:metric_naming_port) { double("MetricNamingPort") }
  let(:logger_port) { double("LoggerPort", debug: nil, info: nil, warn: nil, error: nil) }
  let(:repository) { described_class.new(metric_naming_port: metric_naming_port, logger_port: logger_port) }

  # Common test data
  let(:since_time) { 30.days.ago }
  let(:until_time) { Time.current }
  let(:project_name) { "test-org/test-repo" }

  describe "#resolution_time_stats" do
    let(:github_metrics) do
      [
        double("Metric", value: 4.0, timestamp: since_time + 1.day),
        double("Metric", value: 8.0, timestamp: since_time + 2.days)
      ]
    end

    let(:jira_metrics) do
      [
        double("Metric", value: 6.0, timestamp: since_time + 1.day),
        double("Metric", value: 10.0, timestamp: since_time + 2.days)
      ]
    end

    it "finds issue resolution time statistics" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.time_to_close", {}, since_time)
        .and_return(github_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.time_to_close", {}, since_time)
        .and_return(jira_metrics)

      # Act
      result = repository.resolution_time_stats(since: since_time)

      # Assert
      expect(result[:issue_count]).to eq(4)
      expect(result[:average_hours]).to eq(7.0)
      expect(result[:median_hours]).to eq(7.0)
      expect(result[:p90_hours]).to eq(10.0)
    end

    it "applies source filter if provided" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.time_to_close", {}, since_time)
        .and_return(github_metrics)

      # Don't expect call for Jira metrics when GitHub source is specified

      # Act
      result = repository.resolution_time_stats(since: since_time, source: "github")

      # Assert
      expect(result[:issue_count]).to eq(2)
      expect(result[:average_hours]).to eq(6.0)
    end

    it "applies project filter if provided" do
      # Arrange
      # For GitHub, only repository is set
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.time_to_close", { repository: project_name }, since_time)
        .and_return(github_metrics)

      # For Jira, both project and repository are set (based on implementation)
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.time_to_close", { project: project_name, repository: project_name }, since_time)
        .and_return(jira_metrics)

      # Act
      result = repository.resolution_time_stats(since: since_time, project: project_name)

      # Assert
      expect(result[:issue_count]).to eq(4)
      expect(result[:average_hours]).to eq(7.0)
    end

    it "includes average, median, and p90 statistics" do
      # Arrange
      # Use metrics with more varied values for statistical assertions
      varied_metrics = [
        double("Metric", value: 2.0, timestamp: since_time),
        double("Metric", value: 4.0, timestamp: since_time),
        double("Metric", value: 6.0, timestamp: since_time),
        double("Metric", value: 8.0, timestamp: since_time),
        double("Metric", value: 20.0, timestamp: since_time) # Outlier
      ]

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.time_to_close", {}, since_time)
        .and_return(varied_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.time_to_close", {}, since_time)
        .and_return([])

      # Act
      result = repository.resolution_time_stats(since: since_time)

      # Assert
      expect(result[:average_hours]).to eq(8.0) # (2+4+6+8+20)/5 = 8
      expect(result[:median_hours]).to eq(6.0) # Middle value of [2,4,6,8,20]
      expect(result[:p90_hours]).to eq(20.0) # 90th percentile
    end
  end

  describe "#issue_creation_rates" do
    let(:github_metrics) do
      [
        double("Metric", value: 1.0, timestamp: since_time + 1.day, source: "github"),
        double("Metric", value: 2.0, timestamp: since_time + 8.days, source: "github")
      ]
    end

    let(:jira_metrics) do
      [
        double("Metric", value: 3.0, timestamp: since_time + 2.days, source: "jira"),
        double("Metric", value: 4.0, timestamp: since_time + 9.days, source: "jira")
      ]
    end

    it "finds issue creation rates grouped by interval" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.created", {}, since_time)
        .and_return(github_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.created", {}, since_time)
        .and_return(jira_metrics)

      # Act
      result = repository.issue_creation_rates(since: since_time, interval: "week")

      # Assert
      # The implementation creates intervals for the entire time range
      expect(result.size).to be >= 4 # At least 4 weeks to cover 30 days

      # First week should have GitHub and Jira issues
      first_week = result.find { |r| r[:start_time] == since_time }
      expect(first_week[:count]).to eq(4) # 1 + 3
      expect(first_week[:source_breakdown]).to include("github" => 1, "jira" => 3)
    end

    it "applies source filter if provided" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.created", {}, since_time)
        .and_return(github_metrics)

      # Don't expect call for Jira metrics when GitHub source is specified

      # Act
      result = repository.issue_creation_rates(since: since_time, source: "github")

      # Assert
      first_week = result.find { |r| r[:start_time] == since_time }
      expect(first_week[:source_breakdown]).to include("github")
      expect(first_week[:source_breakdown]).not_to include("jira")
    end

    it "applies project filter if provided" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.created", { repository: project_name }, since_time)
        .and_return(github_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.created", { project: project_name, repository: project_name }, since_time)
        .and_return(jira_metrics)

      # Act
      result = repository.issue_creation_rates(since: since_time, project: project_name)

      # Assert
      first_week = result.find { |r| r[:start_time] == since_time }
      expect(first_week[:count]).to eq(4) # 1 + 3
    end

    it "applies time range filters" do
      # Arrange
      outside_range_metric = double("Metric", value: 5.0, timestamp: until_time + 1.day, source: "github")
      all_metrics = github_metrics + [outside_range_metric]

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.created", {}, since_time)
        .and_return(all_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.created", {}, since_time)
        .and_return([])

      # Act
      result = repository.issue_creation_rates(since: since_time, until_time: until_time)

      # Assert
      # Outside range metric should be filtered out
      first_week = result.find { |r| r[:start_time] == since_time }
      expect(first_week[:source_breakdown]["github"]).to eq(1) # Only the first metric, not the outside range one
    end

    it "groups by the requested interval" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.created", {}, since_time)
        .and_return(github_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.created", {}, since_time)
        .and_return(jira_metrics)

      # Act - use day interval
      result_day = repository.issue_creation_rates(since: since_time, interval: "day")

      # Act - use month interval
      result_month = repository.issue_creation_rates(since: since_time, interval: "month")

      # Assert
      # The implementation creates intervals for the entire time range,
      # which may result in different numbers depending on the exact days
      expect(result_day.size).to be >= 30 # At least 30 days

      # The implementation divides the time range into months, which may result in 1-2 months
      # depending on how the days fall across month boundaries
      expect(result_month.size).to be_between(1, 2) # 1-2 months
    end
  end

  describe "#issue_close_rates" do
    let(:github_metrics) do
      [
        double("Metric", value: 1.0, timestamp: since_time + 1.day, source: "github"),
        double("Metric", value: 2.0, timestamp: since_time + 8.days, source: "github")
      ]
    end

    let(:jira_metrics) do
      [
        double("Metric", value: 2.0, timestamp: since_time + 2.days, source: "jira"),
        double("Metric", value: 3.0, timestamp: since_time + 9.days, source: "jira")
      ]
    end

    it "finds issue close rates grouped by interval" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.closed", {}, since_time)
        .and_return(github_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.closed", {}, since_time)
        .and_return(jira_metrics)

      # Act
      result = repository.issue_close_rates(since: since_time, interval: "week")

      # Assert
      # The implementation creates intervals for the entire time range
      expect(result.size).to be >= 4 # At least 4 weeks to cover 30 days

      # First week should have GitHub and Jira issues
      first_week = result.find { |r| r[:start_time] == since_time }
      expect(first_week[:count]).to eq(3) # 1 + 2
      expect(first_week[:source_breakdown]).to include("github" => 1, "jira" => 2)
    end

    it "applies source filter if provided" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.closed", {}, since_time)
        .and_return(github_metrics)

      # Don't expect call for Jira metrics when GitHub source is specified

      # Act
      result = repository.issue_close_rates(since: since_time, source: "github")

      # Assert
      first_week = result.find { |r| r[:start_time] == since_time }
      expect(first_week[:source_breakdown]).to include("github")
      expect(first_week[:source_breakdown]).not_to include("jira")
    end

    it "applies project filter if provided" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.closed", { repository: project_name }, since_time)
        .and_return(github_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.closed", { project: project_name, repository: project_name }, since_time)
        .and_return(jira_metrics)

      # Act
      result = repository.issue_close_rates(since: since_time, project: project_name)

      # Assert
      first_week = result.find { |r| r[:start_time] == since_time }
      expect(first_week[:count]).to eq(3) # 1 + 2
    end

    it "applies time range filters" do
      # Arrange
      outside_range_metric = double("Metric", value: 5.0, timestamp: until_time + 1.day, source: "github")
      all_metrics = github_metrics + [outside_range_metric]

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.closed", {}, since_time)
        .and_return(all_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.closed", {}, since_time)
        .and_return([])

      # Act
      result = repository.issue_close_rates(since: since_time, until_time: until_time)

      # Assert
      # Outside range metric should be filtered out
      first_week = result.find { |r| r[:start_time] == since_time }
      expect(first_week[:source_breakdown]["github"]).to eq(1) # Only the first metric, not the outside range one
    end

    it "groups by the requested interval" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.closed", {}, since_time)
        .and_return(github_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.closed", {}, since_time)
        .and_return(jira_metrics)

      # Act - use day interval
      result_day = repository.issue_close_rates(since: since_time, interval: "day")

      # Act - use month interval
      result_month = repository.issue_close_rates(since: since_time, interval: "month")

      # Assert
      # The implementation creates intervals for the entire time range,
      # which may result in different numbers depending on the exact days
      expect(result_day.size).to be >= 30 # At least 30 days

      # The implementation divides the time range into months, which may result in 1-2 months
      # depending on how the days fall across month boundaries
      expect(result_month.size).to be_between(1, 2) # 1-2 months
    end
  end

  describe "#backlog_growth" do
    let(:creation_rates) do
      [
        {
          start_time: since_time,
          end_time: since_time + 7.days,
          count: 10,
          source_breakdown: { "github" => 6, "jira" => 4 }
        },
        {
          start_time: since_time + 7.days,
          end_time: since_time + 14.days,
          count: 8,
          source_breakdown: { "github" => 5, "jira" => 3 }
        }
      ]
    end

    let(:close_rates) do
      [
        {
          start_time: since_time,
          end_time: since_time + 7.days,
          count: 6,
          source_breakdown: { "github" => 4, "jira" => 2 }
        },
        {
          start_time: since_time + 7.days,
          end_time: since_time + 14.days,
          count: 9,
          source_breakdown: { "github" => 5, "jira" => 4 }
        }
      ]
    end

    it "finds issue backlog growth grouped by interval" do
      # Arrange
      allow(repository).to receive(:issue_creation_rates)
        .with(since: since_time, until_time: until_time, source: nil, project: nil, interval: "week")
        .and_return(creation_rates)

      allow(repository).to receive(:issue_close_rates)
        .with(since: since_time, until_time: until_time, source: nil, project: nil, interval: "week")
        .and_return(close_rates)

      # Act
      result = repository.backlog_growth(since: since_time, until_time: until_time)

      # Assert
      expect(result.size).to eq(2) # Same as input data

      # First week: 10 created - 6 closed = +4 net change
      expect(result[0][:net_change]).to eq(4)
      expect(result[0][:created]).to eq(10)
      expect(result[0][:closed]).to eq(6)

      # Second week: 8 created - 9 closed = -1 net change (backlog reduction)
      expect(result[1][:net_change]).to eq(-1)
    end

    it "applies source filter if provided" do
      # Arrange
      allow(repository).to receive(:issue_creation_rates)
        .with(since: since_time, until_time: until_time, source: "github", project: nil, interval: "week")
        .and_return(creation_rates)

      allow(repository).to receive(:issue_close_rates)
        .with(since: since_time, until_time: until_time, source: "github", project: nil, interval: "week")
        .and_return(close_rates)

      # Act
      result = repository.backlog_growth(since: since_time, until_time: until_time, source: "github")

      # Assert
      # Just verify that the source parameter is passed along to the underlying methods
      expect(result.size).to eq(2)
    end

    it "applies project filter if provided" do
      # Arrange
      allow(repository).to receive(:issue_creation_rates)
        .with(since: since_time, until_time: until_time, source: nil, project: project_name, interval: "week")
        .and_return(creation_rates)

      allow(repository).to receive(:issue_close_rates)
        .with(since: since_time, until_time: until_time, source: nil, project: project_name, interval: "week")
        .and_return(close_rates)

      # Act
      result = repository.backlog_growth(since: since_time, until_time: until_time, project: project_name)

      # Assert
      # Just verify that the project parameter is passed along to the underlying methods
      expect(result.size).to eq(2)
    end

    it "applies time range filters" do
      # Arrange
      allow(repository).to receive(:issue_creation_rates)
        .with(since: since_time, until_time: until_time, source: nil, project: nil, interval: "week")
        .and_return(creation_rates)

      allow(repository).to receive(:issue_close_rates)
        .with(since: since_time, until_time: until_time, source: nil, project: nil, interval: "week")
        .and_return(close_rates)

      # Act
      result = repository.backlog_growth(since: since_time, until_time: until_time)

      # Assert
      # Just verify that the time parameters are passed along to the underlying methods
      expect(result.size).to eq(2)
    end

    it "groups by the requested interval" do
      # Arrange
      allow(repository).to receive(:issue_creation_rates)
        .with(since: since_time, until_time: until_time, source: nil, project: nil, interval: "day")
        .and_return(creation_rates)

      allow(repository).to receive(:issue_close_rates)
        .with(since: since_time, until_time: until_time, source: nil, project: nil, interval: "day")
        .and_return(close_rates)

      # Act
      result = repository.backlog_growth(since: since_time, until_time: until_time, interval: "day")

      # Assert
      # Just verify that the interval parameter is passed along to the underlying methods
      expect(result.size).to eq(2)
    end

    it "calculates net change between creation and closure" do
      # Arrange
      allow(repository).to receive(:issue_creation_rates)
        .with(since: since_time, until_time: until_time, source: nil, project: nil, interval: "week")
        .and_return(creation_rates)

      allow(repository).to receive(:issue_close_rates)
        .with(since: since_time, until_time: until_time, source: nil, project: nil, interval: "week")
        .and_return(close_rates)

      # Act
      result = repository.backlog_growth(since: since_time, until_time: until_time)

      # Assert
      # First week: GitHub +2 (6 created - 4 closed), Jira +2 (4 created - 2 closed)
      expect(result[0][:source_breakdown]).to include(
        "github" => 2,
        "jira" => 2
      )

      # Second week: GitHub 0 (5 created - 5 closed), Jira -1 (3 created - 4 closed)
      expect(result[1][:source_breakdown]).to include(
        "github" => 0,
        "jira" => -1
      )
    end
  end

  describe "#assignee_workload" do
    let(:github_assignee_metrics) do
      [
        double("Metric",
               value: 5,
               timestamp: since_time + 1.day,
               source: "github",
               dimensions: { "assignee" => "user1" }),
        double("Metric",
               value: 3,
               timestamp: since_time + 2.days,
               source: "github",
               dimensions: { "assignee" => "user2" }),
        double("Metric",
               value: 7,
               timestamp: since_time + 3.days,
               source: "github",
               dimensions: { "assignee" => "user1" })
      ]
    end

    it "finds issue assignee workload" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.assignee_count", {}, since_time)
        .and_return(github_assignee_metrics)

      # Act
      result = repository.assignee_workload(since: since_time)

      # Assert
      expect(result.size).to eq(2) # Two distinct assignees

      # User1 has two GitHub metrics (5+7)
      user1 = result.find { |r| r[:assignee] == "user1" }
      expect(user1[:issue_count]).to eq(12) # 5 + 7

      # User2 has one GitHub metric with value 3
      user2 = result.find { |r| r[:assignee] == "user2" }
      expect(user2[:issue_count]).to eq(3)
    end

    it "applies source filter if provided" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.assignee_count", {}, since_time)
        .and_return(github_assignee_metrics)

      # Act
      result = repository.assignee_workload(since: since_time, source: "github")

      # Assert
      expect(result.size).to eq(2) # Two GitHub assignees

      # Only GitHub metrics are included
      user1 = result.find { |r| r[:assignee] == "user1" }
      expect(user1[:issue_count]).to eq(12) # 5 + 7
    end

    it "applies project filter if provided" do
      # Arrange
      # For GitHub, only repository is set
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.assignee_count", { repository: project_name }, since_time)
        .and_return(github_assignee_metrics)

      # Act
      result = repository.assignee_workload(since: since_time, project: project_name)

      # Assert
      expect(result.size).to eq(2) # Two distinct assignees

      # User1 should have metrics from GitHub only
      user1 = result.find { |r| r[:assignee] == "user1" }
      expect(user1[:issue_count]).to eq(12) # 5 + 7
    end

    it "limits results if requested" do
      # Arrange
      # Create more test data with different assignees
      more_metrics = github_assignee_metrics + [
        double("Metric",
               value: 2,
               timestamp: since_time + 4.days,
               source: "github",
               dimensions: { "assignee" => "user3" })
      ]

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.assignee_count", {}, since_time)
        .and_return(more_metrics)

      # Act
      result = repository.assignee_workload(since: since_time, limit: 2)

      # Assert
      expect(result.size).to eq(2) # Limited to top 2 assignees

      # User1 has the highest count (12)
      expect(result[0][:assignee]).to eq("user1")
      expect(result[0][:issue_count]).to eq(12) # 5 + 7

      # User2 has the second highest count (3)
      expect(result[1][:assignee]).to eq("user2")
      expect(result[1][:issue_count]).to eq(3)
    end
  end

  describe "#issue_type_distribution" do
    let(:github_metrics) do
      [
        double("Metric",
               value: 8,
               timestamp: since_time + 1.day,
               source: "github",
               dimensions: { "type" => "bug" }),
        double("Metric",
               value: 5,
               timestamp: since_time + 2.days,
               source: "github",
               dimensions: { "type" => "feature" })
      ]
    end

    let(:jira_metrics) do
      [
        double("Metric",
               value: 6,
               timestamp: since_time + 1.day,
               source: "jira",
               dimensions: { "type" => "bug" }),
        double("Metric",
               value: 4,
               timestamp: since_time + 2.days,
               source: "jira",
               dimensions: { "type" => "improvement" })
      ]
    end

    it "finds issue type distribution" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.type_distribution", {}, since_time)
        .and_return(github_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.type_distribution", {}, since_time)
        .and_return(jira_metrics)

      # Act
      result = repository.issue_type_distribution(since: since_time)

      # Assert
      expect(result.size).to eq(3) # Three distinct issue types

      # Bug has highest count (8 + 6 = 14)
      expect(result[0][:type]).to eq("bug")
      expect(result[0][:count]).to eq(14)
      expect(result[0][:sources]).to include("github" => 8, "jira" => 6)

      # Feature has second highest count (5)
      expect(result[1][:type]).to eq("feature")
      expect(result[1][:count]).to eq(5)

      # Improvement has lowest count (4)
      expect(result[2][:type]).to eq("improvement")
      expect(result[2][:count]).to eq(4)
    end

    it "applies source filter if provided" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.type_distribution", {}, since_time)
        .and_return(github_metrics)

      # Don't expect call for Jira metrics when GitHub source is specified

      # Act
      result = repository.issue_type_distribution(since: since_time, source: "github")

      # Assert
      expect(result.size).to eq(2) # Only GitHub types
      expect(result[0][:type]).to eq("bug")
      expect(result[0][:count]).to eq(8)
      expect(result[0][:sources]).to include("github" => 8)
      expect(result[0][:sources]).not_to include("jira")
    end

    it "applies project filter if provided" do
      # Arrange
      # For GitHub, only repository is set
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.type_distribution", { repository: project_name }, since_time)
        .and_return(github_metrics)

      # For Jira, both project and repository are set
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.type_distribution", { project: project_name, repository: project_name }, since_time)
        .and_return(jira_metrics)

      # Act
      result = repository.issue_type_distribution(since: since_time, project: project_name)

      # Assert
      expect(result.size).to eq(3) # Three distinct issue types

      # Verify the metrics were combined correctly
      bug_result = result.find { |r| r[:type] == "bug" }
      expect(bug_result[:count]).to eq(14) # 8 from GitHub + 6 from Jira
    end

    it "normalizes issue types across different sources" do
      # Arrange
      # Add metrics with types that should be normalized
      metrics_with_custom_types = [
        double("Metric",
               value: 3,
               timestamp: since_time + 1.day,
               source: "github",
               dimensions: { "type" => "unknown" }),
        double("Metric",
               value: 2,
               timestamp: since_time + 2.days,
               source: "jira",
               dimensions: { "type" => nil })
      ]

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.type_distribution", {}, since_time)
        .and_return(github_metrics + [metrics_with_custom_types[0]])

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.type_distribution", {}, since_time)
        .and_return(jira_metrics + [metrics_with_custom_types[1]])

      # Act
      result = repository.issue_type_distribution(since: since_time)

      # Assert
      # Verify that nil and "unknown" types are both mapped to "unknown"
      unknown_type = result.find { |r| r[:type] == "unknown" }
      expect(unknown_type).not_to be_nil
      expect(unknown_type[:count]).to eq(5) # 3 + 2
    end
  end

  describe "#issue_priority_distribution" do
    let(:github_metrics) do
      [
        double("Metric",
               value: 7,
               timestamp: since_time + 1.day,
               source: "github",
               dimensions: { "priority" => "priority:high" }),
        double("Metric",
               value: 4,
               timestamp: since_time + 2.days,
               source: "github",
               dimensions: { "priority" => "priority:medium" }),
        double("Metric",
               value: 3,
               timestamp: since_time + 3.days,
               source: "github",
               dimensions: { "priority" => "priority:low" })
      ]
    end

    let(:jira_metrics) do
      [
        double("Metric",
               value: 2,
               timestamp: since_time + 1.day,
               source: "jira",
               dimensions: { "priority" => "highest" }),
        double("Metric",
               value: 5,
               timestamp: since_time + 2.days,
               source: "jira",
               dimensions: { "priority" => "high" }),
        double("Metric",
               value: 4,
               timestamp: since_time + 3.days,
               source: "jira",
               dimensions: { "priority" => "medium" })
      ]
    end

    it "finds issue priority distribution" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.priority_distribution", {}, since_time)
        .and_return(github_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.priority_distribution", {}, since_time)
        .and_return(jira_metrics)

      # Act
      result = repository.issue_priority_distribution(since: since_time)

      # Assert
      expect(result.size).to eq(4) # Four distinct priorities after normalization

      # First should be critical (mapped from highest)
      expect(result[0][:priority]).to eq("critical")
      expect(result[0][:count]).to eq(2)

      # Second should be high (mapped from both systems)
      expect(result[1][:priority]).to eq("high")
      expect(result[1][:count]).to eq(12) # 7 from GitHub + 5 from Jira

      # Third should be medium (mapped from both systems)
      expect(result[2][:priority]).to eq("medium")
      expect(result[2][:count]).to eq(8) # 4 from GitHub + 4 from Jira
    end

    it "applies source filter if provided" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.priority_distribution", {}, since_time)
        .and_return(github_metrics)

      # Don't expect call for Jira metrics when GitHub source is specified

      # Act
      result = repository.issue_priority_distribution(since: since_time, source: "github")

      # Assert
      expect(result.size).to eq(3) # Only GitHub priorities
      expect(result[0][:priority]).to eq("high")
      expect(result[0][:count]).to eq(7)
      expect(result[0][:sources]).to include("github" => 7)
      expect(result[0][:sources]).not_to include("jira")
    end

    it "applies project filter if provided" do
      # Arrange
      # For GitHub, only repository is set
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.priority_distribution", { repository: project_name }, since_time)
        .and_return(github_metrics)

      # For Jira, both project and repository are set
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.priority_distribution", { project: project_name, repository: project_name }, since_time)
        .and_return(jira_metrics)

      # Act
      result = repository.issue_priority_distribution(since: since_time, project: project_name)

      # Assert
      expect(result.size).to eq(4) # Four distinct priorities after normalization

      # Verify the high priority metrics were combined correctly
      high_priority = result.find { |r| r[:priority] == "high" }
      expect(high_priority[:count]).to eq(12) # 7 from GitHub + 5 from Jira
    end

    it "normalizes priorities across different sources" do
      # Arrange - we'll use the existing metrics which have different priority formats
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.priority_distribution", {}, since_time)
        .and_return(github_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.priority_distribution", {}, since_time)
        .and_return(jira_metrics)

      # Act
      result = repository.issue_priority_distribution(since: since_time)

      # Assert
      # Verify that priorities are normalized according to the mapping:
      # - "priority:high" (GitHub) and "high" (Jira) => "high"
      # - "priority:medium" (GitHub) and "medium" (Jira) => "medium"
      # - "highest" (Jira) => "critical"
      high_priority = result.find { |r| r[:priority] == "high" }
      expect(high_priority[:count]).to eq(12) # 7 from GitHub + 5 from Jira

      medium_priority = result.find { |r| r[:priority] == "medium" }
      expect(medium_priority[:count]).to eq(8) # 4 from GitHub + 4 from Jira

      critical_priority = result.find { |r| r[:priority] == "critical" }
      expect(critical_priority[:count]).to eq(2) # 2 from Jira
    end
  end

  describe "#issue_comment_activity" do
    let(:github_comment_metrics) do
      [
        double("Metric",
               value: 15,
               timestamp: since_time + 1.day,
               source: "github",
               dimensions: {
                 "issue_id" => "github/repo#123",
                 "title" => "Important Bug",
                 "url" => "https://github.com/repo/issues/123"
               }),
        double("Metric",
               value: 8,
               timestamp: since_time + 2.days,
               source: "github",
               dimensions: {
                 "issue_id" => "github/repo#456",
                 "title" => "Feature Request",
                 "url" => "https://github.com/repo/issues/456"
               })
      ]
    end

    let(:jira_comment_metrics) do
      [
        double("Metric",
               value: 12,
               timestamp: since_time + 3.days,
               source: "jira",
               dimensions: {
                 "issue_key" => "PROJ-123",
                 "title" => "Performance Issue",
                 "url" => "https://jira.company.com/browse/PROJ-123"
               })
      ]
    end

    it "finds issue comment activity" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.comment_count", {}, since_time)
        .and_return(github_comment_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.comment_count", {}, since_time)
        .and_return(jira_comment_metrics)

      # Act
      result = repository.issue_comment_activity(since: since_time)

      # Assert
      expect(result.size).to eq(3) # Three distinct issues

      # Check that appropriate data is extracted and returned
      github_issue = result.find { |i| i[:issue_id] == "github/repo#123" }
      expect(github_issue).not_to be_nil
      expect(github_issue[:title]).to eq("Important Bug")
      expect(github_issue[:comment_count]).to eq(15)

      jira_issue = result.find { |i| i[:issue_id] == "PROJ-123" }
      expect(jira_issue).not_to be_nil
      expect(jira_issue[:title]).to eq("Performance Issue")
      expect(jira_issue[:comment_count]).to eq(12)
    end

    it "applies project filter if provided" do
      # Arrange
      # For GitHub, only repository is set
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.comment_count", { repository: project_name }, since_time)
        .and_return(github_comment_metrics)

      # For Jira, both project and repository are set
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.comment_count", { project: project_name, repository: project_name }, since_time)
        .and_return(jira_comment_metrics)

      # Act
      result = repository.issue_comment_activity(since: since_time, project: project_name)

      # Assert
      expect(result.size).to eq(3) # All three issues are returned

      # Verify that both GitHub and JIRA metrics are included
      sources = result.map { |item| item[:source] }
      expect(sources).to include("github", "jira")

      # Verify comment counts are set correctly
      github_issue = result.find { |i| i[:issue_id] == "github/repo#123" }
      expect(github_issue[:comment_count]).to eq(15)

      jira_issue = result.find { |i| i[:issue_id] == "PROJ-123" }
      expect(jira_issue[:comment_count]).to eq(12)
    end

    it "limits results if requested" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.comment_count", {}, since_time)
        .and_return(github_comment_metrics)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("jira.issue.comment_count", {}, since_time)
        .and_return(jira_comment_metrics)

      # Act
      result = repository.issue_comment_activity(since: since_time, limit: 2)

      # Assert
      expect(result.size).to eq(2) # Limited to 2 issues

      # Since we're sorting by comment count descending, the first two should be
      # github#123 (15 comments) and PROJ-123 (12 comments)
      expect(result[0][:issue_id]).to eq("github/repo#123")
      expect(result[0][:comment_count]).to eq(15)
      expect(result[1][:issue_id]).to eq("PROJ-123")
      expect(result[1][:comment_count]).to eq(12)
    end

    it "applies source filter if provided" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.issue.comment_count", {}, since_time)
        .and_return(github_comment_metrics)

      # Don't expect call for Jira metrics when GitHub source is specified

      # Act
      result = repository.issue_comment_activity(since: since_time, source: "github")

      # Assert
      expect(result.map { |item| item[:source] }).to all(eq("github"))
      expect(result.map { |item| item[:issue_id] }).to contain_exactly("github/repo#123", "github/repo#456")

      # Verify comment counts
      result.each do |issue|
        if issue[:issue_id] == "github/repo#123"
          expect(issue[:comment_count]).to eq(15)
        elsif issue[:issue_id] == "github/repo#456"
          expect(issue[:comment_count]).to eq(8)
        end
      end
    end
  end

  describe "#build_issue_base_query" do
    let(:domain_metric_query) { double("ActiveRecord::Relation") }
    let(:time_filtered_query) { double("ActiveRecord::Relation") }
    let(:source_filtered_query) { double("ActiveRecord::Relation") }
    let(:project_filtered_query) { double("ActiveRecord::Relation") }

    it "builds a base query that filters by time period" do
      # Arrange
      allow(DomainMetric).to receive(:where).with("recorded_at >= ?", since_time).and_return(time_filtered_query)
      allow(time_filtered_query).to receive(:where).and_return(source_filtered_query)

      # Act
      repository.send(:build_issue_base_query, since: since_time)

      # Assert
      expect(DomainMetric).to have_received(:where).with("recorded_at >= ?", since_time)
    end

    it "applies source filter if provided" do
      # Arrange
      allow(DomainMetric).to receive(:where).with("recorded_at >= ?", since_time).and_return(time_filtered_query)
      allow(time_filtered_query).to receive(:where).with("name LIKE ?",
                                                         "github.issue.%").and_return(source_filtered_query)

      # Act
      repository.send(:build_issue_base_query, since: since_time, source: "github")

      # Assert
      expect(time_filtered_query).to have_received(:where).with("name LIKE ?", "github.issue.%")
    end

    it "applies project filter if provided" do
      # Arrange
      allow(DomainMetric).to receive(:where).with("recorded_at >= ?", since_time).and_return(time_filtered_query)
      allow(time_filtered_query).to receive(:where).and_return(source_filtered_query)

      # This test verifies that the query searches for both repository and project dimensions
      # to accommodate different metric source systems (GitHub, Jira)
      allow(source_filtered_query).to receive(:where).with(
        "dimensions @> ? OR dimensions @> ?",
        { repository: project_name }.to_json,
        { project: project_name }.to_json
      ).and_return(project_filtered_query)

      # Act
      repository.send(:build_issue_base_query, since: since_time, project: project_name)

      # Assert
      # Verify both repository (for GitHub) and project (for Jira) dimensions are checked
      expect(source_filtered_query).to have_received(:where).with(
        "dimensions @> ? OR dimensions @> ?",
        { repository: project_name }.to_json,
        { project: project_name }.to_json
      )
    end

    it "filters for issue-related metrics" do
      # Arrange
      allow(DomainMetric).to receive(:where).with("recorded_at >= ?", since_time).and_return(time_filtered_query)
      allow(time_filtered_query).to receive(:where).with("name LIKE '%.issue.%'").and_return(source_filtered_query)

      # Act
      repository.send(:build_issue_base_query, since: since_time)

      # Assert
      expect(time_filtered_query).to have_received(:where).with("name LIKE '%.issue.%'")
    end
  end
end
