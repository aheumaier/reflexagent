# frozen_string_literal: true

class DashboardsController < ApplicationController
  def dashboard
    redirect_to engineering_dashboard_path
  end

  def engineering
    # Get time range from params with default of 30 days
    @days = (params[:days] || 30).to_i
    @since_date = @days.days.ago.utc

    # Fetch metrics using dashboard adapter with consistent error handling
    @commit_metrics = with_dashboard_adapter(:get_commit_metrics, default_commit_metrics, time_period: @days)
    @dora_metrics = with_dashboard_adapter(:get_dora_metrics, default_dora_metrics, time_period: @days)
    @ci_cd_metrics = with_dashboard_adapter(:get_cicd_metrics, default_cicd_metrics, time_period: @days)
    @repo_metrics = with_dashboard_adapter(:get_repository_metrics, default_repo_metrics, time_period: @days)
    @team_metrics = with_dashboard_adapter(:get_team_metrics, default_team_metrics, time_period: @days)
    @recent_alerts = with_dashboard_adapter(:get_recent_alerts, [], time_period: @days, limit: 5)

    # For the select dropdown
    @time_range_options = [
      ["Last 7 days", 7],
      ["Last 30 days", 30],
      ["Last 90 days", 90]
    ]
  end

  def commit_metrics
    # Get time range from params with default of 30 days
    @days = (params[:days] || 30).to_i

    # Store selected period for UI highlighting
    @selected_period = @days

    # Get repository filter
    @repository = params[:repository]

    # Get commit metrics data using the dashboard adapter
    @commit_metrics = with_dashboard_adapter(
      :get_repository_commit_analysis,
      default_commit_metrics,
      repository: @repository || "unknown",
      time_period: @days
    )

    # If no repository was provided but we got one from the adapter, update @repository
    @repository ||= @commit_metrics[:repository] if @commit_metrics[:repository] != "unknown"

    # Get list of repositories for filter dropdown using the dashboard adapter
    @repositories = with_dashboard_adapter(
      :get_available_repositories,
      [],
      time_period: @days,
      limit: 50
    )
  end

  private

  # Default metrics to prevent UI errors
  def default_repo_metrics
    {
      push_counts: {},
      active_repos: {},
      commit_volume: {},
      pr_metrics: { open: {}, closed: {}, merged: {} }
    }
  end

  def default_cicd_metrics
    {
      builds: {
        total: 0,
        success_rate: 0,
        avg_duration: 0,
        builds_by_day: {},
        success_by_day: {},
        builds_by_workflow: {},
        longest_workflow_durations: {},
        flaky_builds: []
      },
      deployments: {
        total: 0,
        success_rate: 0,
        avg_duration: 0,
        deployment_frequency: 0.0,
        deploys_by_day: {},
        success_rate_by_day: {},
        deploys_by_workflow: {},
        durations_by_environment: {},
        common_failure_reasons: {}
      }
    }
  end

  def default_dora_metrics
    {
      deployment_frequency: { value: 0, rating: "unknown", days_with_deployments: 0, total_days: 30,
                              total_deployments: 0 },
      lead_time: { value: 0, rating: "unknown", sample_size: 0 },
      time_to_restore: { value: 0, rating: "unknown", sample_size: 0 },
      change_failure_rate: { value: 0, rating: "unknown", failures: 0, deployments: 0 }
    }
  end

  def default_team_metrics
    {
      top_contributors: {},
      team_velocity: 0,
      pr_review_time: 0
    }
  end

  # Default commit metrics to prevent UI errors
  def default_commit_metrics
    {
      repository: "unknown",
      directory_hotspots: [],
      file_extension_hotspots: [],
      commit_types: [],
      breaking_changes: { total: 0, by_author: [] },
      author_activity: [],
      commit_volume: { total_commits: 0, days_with_commits: 0, days_analyzed: 0, commits_per_day: 0,
                       commit_frequency: 0, daily_activity: [] },
      code_churn: { additions: 0, deletions: 0, total_churn: 0, churn_ratio: 0 }
    }
  end

  # Safely call methods on the dashboard adapter with default fallback
  def with_dashboard_adapter(method_name, default_value, **)
    result = get_dashboard_adapter.send(method_name, **)
    result.nil? ? default_value : result
  rescue StandardError => e
    Rails.logger.error("Dashboard adapter error: #{method_name} - #{e.message}")
    default_value
  end

  def get_dashboard_adapter
    @dashboard_adapter ||= Dashboard::DashboardAdapter.new(
      storage_port: Repositories::MetricRepository.new(logger_port: Rails.logger),
      cache_port: nil,
      logger_port: Rails.logger
    )
  end
end
