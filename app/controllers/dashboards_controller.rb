# frozen_string_literal: true

class DashboardsController < ApplicationController
  def dashboard
    redirect_to engineering_dashboard_path
  end

  def engineering
    # Get time range from params with default of 30 days
    @days = (params[:days] || 30).to_i
    @since_date = @days.days.ago.utc

    # Initialize data for dashboard with default values
    metrics_service = ServiceFactory.create_metrics_service
    dora_service = ServiceFactory.create_dora_service

    # Calculate / pull metrics for display with error handling
    begin
      @commit_metrics = pull_commit_metrics(metrics_service)
    rescue StandardError => e
      Rails.logger.error("Error fetching commit metrics: #{e.message}")
      @commit_metrics = default_commit_metrics
    end

    begin
      @dora_metrics = pull_dora_metrics(dora_service)
    rescue StandardError => e
      Rails.logger.error("Error fetching DORA metrics: #{e.message}")
      @dora_metrics = default_dora_metrics
    end

    begin
      @ci_cd_metrics = pull_cicd_metrics(metrics_service)
      # Ensure the nested structure exists to prevent nil errors
      @ci_cd_metrics ||= {}
      @ci_cd_metrics[:builds] ||= { success_rate: 0, total: 0, avg_duration: 0 }
      @ci_cd_metrics[:deployments] ||= { success_rate: 0, total: 0, avg_duration: 0 }
    rescue StandardError => e
      Rails.logger.error("Error fetching CI/CD metrics: #{e.message}")
      @ci_cd_metrics = default_cicd_metrics
    end

    begin
      @repo_metrics = fetch_repository_metrics(@days)
    rescue StandardError => e
      Rails.logger.error("Error fetching repository metrics: #{e.message}")
      @repo_metrics = default_repo_metrics
    end

    begin
      @team_metrics = fetch_team_metrics(@days)
    rescue StandardError => e
      Rails.logger.error("Error fetching team metrics: #{e.message}")
      @team_metrics = default_team_metrics
    end

    begin
      @recent_alerts = fetch_recent_alerts(@days)
    rescue StandardError => e
      Rails.logger.error("Error fetching alerts: #{e.message}")
      @recent_alerts = []
    end

    # For the select dropdown
    @time_range_options = [
      ["Last 7 days", 7],
      ["Last 30 days", 30],
      ["Last 90 days", 90]
    ]
  end

  def commit_metrics
    # Get time range from params with logging
    @days = (params[:days] || 30).to_i
    Rails.logger.info("Commit metrics dashboard filtering for #{@days} days")

    # Store selected period for UI highlighting
    @selected_period = @days

    # Get repository filter
    @repository = params[:repository]

    begin
      # Get commit metrics data
      @commit_metrics = fetch_commit_metrics(@days, @repository)
    rescue StandardError => e
      Rails.logger.error("Error fetching commit metrics: #{e.message}")
      @commit_metrics = default_commit_metrics
    end

    # Get list of repositories for filter dropdown
    begin
      @repositories = fetch_repositories(@days)
    rescue StandardError => e
      Rails.logger.error("Error fetching repositories list: #{e.message}")
      @repositories = []
    end

    # Log completion
    Rails.logger.info("Commit metrics data fetched successfully for #{@days} days period")
  end

  private

  def pull_commit_metrics(metrics_service)
    commits_by_day = metrics_service.time_series(
      "github.push.total",
      days: @days,
      interval: "day"
    )

    authors_by_day = metrics_service.time_series(
      "github.push.unique_authors",
      days: @days,
      interval: "day",
      unique_by: "author"
    )

    {
      commits_by_day: commits_by_day,
      total_commits: commits_by_day.values.sum,
      authors_by_day: authors_by_day,
      unique_authors: authors_by_day.values.sum
    }
  end

  def pull_dora_metrics(dora_service)
    # Get DORA metrics for the selected time range
    {
      deployment_frequency: dora_service.deployment_frequency(@days),
      lead_time: dora_service.lead_time_for_changes(@days),
      change_failure_rate: dora_service.change_failure_rate(@days),
      time_to_restore: dora_service.time_to_restore_service(@days)
    }
  end

  def pull_cicd_metrics(metrics_service)
    # Get CI/CD metrics for display
    builds = metrics_service.time_series(
      "github.ci.build.total",
      days: @days,
      interval: "day"
    ) || {}

    build_durations = metrics_service.aggregate(
      "github.ci.build.duration",
      days: @days,
      aggregation: "avg"
    ) || 0

    # Try with the new prefix first, then fallback to old
    deploys = metrics_service.time_series(
      "github.ci.deploy.total",
      days: @days,
      interval: "day"
    ) || {}

    deploy_durations = metrics_service.aggregate(
      "github.ci.deploy.duration",
      days: @days,
      aggregation: "avg"
    ) || 0

    # Also check for successful deployments from workflow runs
    if deploys.empty?
      # Try to derive deploy metrics from workflow runs that were successful
      deploy_workflow_runs = DomainMetric.where("name LIKE ?", "github.workflow_run.completed")
                                         .where("dimensions->>'conclusion' = ?", "success")
                                         .where("recorded_at > ?", @days.days.ago)

      if deploy_workflow_runs.any?
        # Group by day
        deploy_workflow_runs_by_day = deploy_workflow_runs.group_by do |metric|
          metric.recorded_at.strftime("%Y-%m-%d")
        end

        # Convert to the format expected by the dashboard
        deploys = {}
        deploy_workflow_runs_by_day.each do |day, metrics|
          deploys[day] = metrics.count
        end
      end
    end

    # Calculate success rates or use default values
    build_success_rate = metrics_service.success_rate("github.ci.build", @days) || 0
    deploy_success_rate = metrics_service.success_rate("github.ci.deploy", @days) || 0

    {
      builds_by_day: builds,
      total_builds: builds.values.sum,
      average_build_duration: build_durations,
      deploys_by_day: deploys,
      total_deploys: deploys.values.sum,
      average_deploy_duration: deploy_durations,
      # Ensure these nested structures exist for the view
      builds: {
        total: builds.values.sum,
        success_rate: build_success_rate.round(1),
        avg_duration: build_durations.to_f.round(1)
      },
      deployments: {
        total: deploys.values.sum,
        success_rate: deploy_success_rate.round(1),
        avg_duration: deploy_durations.to_f.round(1)
      }
    }
  end

  def fetch_repository_metrics(days = 30)
    metrics_service = ServiceFactory.create_metrics_service

    {
      # Daily push counts by repository
      push_counts: metrics_service.aggregate_metrics("github.push.total", "daily", days),

      # Recent active repositories
      active_repos: metrics_service.top_metrics("github.push.total",
                                                dimension: "repository",
                                                limit: 5,
                                                days: days),

      # Commit volume - use daily aggregates
      commit_volume: metrics_service.aggregate_metrics("github.push.commits.daily", "daily", days),

      # PR metrics
      pr_metrics: {
        open: metrics_service.aggregate_metrics("github.pull_request.opened", "daily", days),
        closed: metrics_service.aggregate_metrics("github.pull_request.closed", "daily", days),
        merged: metrics_service.aggregate_metrics("github.pull_request.merged", "daily", days)
      }
    }
  end

  def fetch_cicd_metrics(days = 30)
    metrics_service = ServiceFactory.create_metrics_service

    {
      # Build statistics
      builds: {
        # Try the new prefix first, fall back to old prefix
        total: metrics_service.aggregate_metrics("github.ci.build.total", "daily", days) ||
          metrics_service.aggregate_metrics("ci.build.total", "daily", days),
        success_rate: metrics_service.success_rate("github.ci.build", days) ||
          metrics_service.success_rate("ci.build", days),
        avg_duration: metrics_service.average_metric("github.ci.build.duration", days) ||
          metrics_service.average_metric("ci.build.duration", days)
      },

      # Deployment statistics
      deployments: {
        # Try the new prefix first, fall back to old prefix
        total: metrics_service.aggregate_metrics("github.ci.deploy.total", "daily", days) ||
          metrics_service.aggregate_metrics("ci.deploy.total", "daily", days),
        success_rate: metrics_service.success_rate("github.ci.deploy", days) ||
          metrics_service.success_rate("ci.deploy", days),
        avg_duration: metrics_service.average_metric("github.ci.deploy.duration", days) ||
          metrics_service.average_metric("ci.deploy.duration", days)
      }
    }
  end

  def fetch_dora_metrics(days = 30)
    # Try to get pre-calculated DORA metrics from the database
    metric_repository = DependencyContainer.resolve(:metric_repository)

    # We need to handle how the period_days value is stored in the database
    # It's stored as an integer in the JSON dimensions
    Rails.logger.info("Looking for pre-calculated DORA metrics with period_days=#{days}")

    # Deployment Frequency - Find any metrics with the exact period_days value
    deployment_frequency_metrics = DomainMetric.where(name: "dora.deployment_frequency")
                                               .where("dimensions->>'period_days' = ?", days.to_s)
                                               .order(recorded_at: :desc)
                                               .limit(1)
    deployment_frequency_metric = deployment_frequency_metrics.first

    # Lead Time
    lead_time_metrics = DomainMetric.where(name: "dora.lead_time")
                                    .where("dimensions->>'period_days' = ?", days.to_s)
                                    .order(recorded_at: :desc)
                                    .limit(1)
    lead_time_metric = lead_time_metrics.first

    # Time to Restore
    time_to_restore_metrics = DomainMetric.where(name: "dora.time_to_restore")
                                          .where("dimensions->>'period_days' = ?", days.to_s)
                                          .order(recorded_at: :desc)
                                          .limit(1)
    time_to_restore_metric = time_to_restore_metrics.first

    # Change Failure Rate
    change_failure_rate_metrics = DomainMetric.where(name: "dora.change_failure_rate")
                                              .where("dimensions->>'period_days' = ?", days.to_s)
                                              .order(recorded_at: :desc)
                                              .limit(1)
    change_failure_rate_metric = change_failure_rate_metrics.first

    # If we found all pre-calculated metrics, use them
    if deployment_frequency_metric && lead_time_metric &&
       time_to_restore_metric && change_failure_rate_metric

      Rails.logger.info("Using pre-calculated DORA metrics for #{days} days period")

      return {
        # Deployment Frequency
        deployment_frequency: {
          value: deployment_frequency_metric.value,
          rating: deployment_frequency_metric.dimensions["rating"],
          days_with_deployments: deployment_frequency_metric.dimensions["days_with_deployments"].to_i,
          total_days: days,
          total_deployments: deployment_frequency_metric.dimensions["total_deployments"].to_i
        },

        # Lead Time for Changes
        lead_time: {
          value: lead_time_metric.value,
          rating: lead_time_metric.dimensions["rating"],
          sample_size: lead_time_metric.dimensions["sample_size"].to_i
        },

        # Time to Restore Service
        time_to_restore: {
          value: time_to_restore_metric.value,
          rating: time_to_restore_metric.dimensions["rating"],
          sample_size: time_to_restore_metric.dimensions["sample_size"].to_i
        },

        # Change Failure Rate
        change_failure_rate: {
          value: change_failure_rate_metric.value,
          rating: change_failure_rate_metric.dimensions["rating"],
          failures: change_failure_rate_metric.dimensions["failures"].to_f,
          deployments: change_failure_rate_metric.dimensions["deployments"].to_f
        }
      }
    end

    # If pre-calculated metrics are not available, calculate them on-demand
    Rails.logger.info("Pre-calculated DORA metrics not found, calculating on-demand for #{days} days period")
    dora_service = ServiceFactory.create_dora_service

    {
      # Deployment Frequency
      deployment_frequency: dora_service.deployment_frequency(days),

      # Lead Time for Changes
      lead_time: dora_service.lead_time_for_changes(days),

      # Time to Restore Service
      time_to_restore: dora_service.time_to_restore_service(days),

      # Change Failure Rate
      change_failure_rate: dora_service.change_failure_rate(days)
    }
  end

  def fetch_team_metrics(days = 30)
    metrics_service = ServiceFactory.create_metrics_service
    weeks = [days / 7, 1].max # Convert days to weeks, minimum 1

    {
      # Top contributors
      top_contributors: metrics_service.top_metrics("github.push.unique_authors",
                                                    dimension: "author",
                                                    limit: 5,
                                                    days: days),

      # Team velocity
      team_velocity: metrics_service.team_velocity(weeks),

      # PR review time
      pr_review_time: metrics_service.average_metric("github.pull_request.review_time", days)
    }
  end

  def fetch_recent_alerts(days = 30)
    alert_service = ServiceFactory.create_alert_service

    # Get actual alert data
    alerts = alert_service.recent_alerts(limit: 5, days: days)

    # If no actual alerts, create sample data to display
    if alerts.nil? || alerts.empty?
      # Sample alerts for UI testing
      sample_alerts = []
      severities = ["warning", "critical", "warning", "info", "critical"]
      statuses = ["active", "active", "active", "resolved", "active"]

      5.times do |i|
        sample_alerts << OpenStruct.new(
          id: i + 1,
          name: "Sample Alert #{i + 1}",
          severity: severities[i],
          status: statuses[i],
          timestamp: Time.now - (i * 3600)
        )
      end

      return sample_alerts
    end

    alerts
  end

  # New method to fetch commit metrics data
  def fetch_commit_metrics(days = 30, repository = nil)
    metrics_service = ServiceFactory.create_metrics_service
    since_date = days.days.ago

    # Create a use case instance for analyzing commits
    analyze_commits_use_case = UseCaseFactory.create_analyze_commits

    # Call the use case to get detailed commit analysis
    # If repository is provided, filter by that repository
    if repository.present?
      commit_analysis = analyze_commits_use_case.call(repository: repository, since: since_date)
    else
      # Get the top active repository if none specified
      top_repo = metrics_service.top_metrics("github.push.total", dimension: "repository", limit: 1,
                                                                  days: days).keys.first

      # Use the top repository or fallback to a default
      repository = top_repo || "unknown"
      commit_analysis = analyze_commits_use_case.call(repository: repository, since: since_date)
    end

    # Return the analysis results with repository information
    {
      repository: repository,
      directory_hotspots: commit_analysis[:directory_hotspots],
      file_extension_hotspots: commit_analysis[:file_extension_hotspots],
      commit_types: commit_analysis[:commit_types],
      breaking_changes: commit_analysis[:breaking_changes],
      author_activity: commit_analysis[:author_activity],
      commit_volume: commit_analysis[:commit_volume],
      code_churn: commit_analysis[:code_churn]
    }
  end

  # Get list of repositories for filter dropdown
  def fetch_repositories(days = 30)
    metrics_service = ServiceFactory.create_metrics_service

    # Get active repositories sorted by activity
    repos = metrics_service.top_metrics(
      "github.push.total",
      dimension: "repository",
      limit: 50, # Get a reasonable number of repositories
      days: days
    ).keys

    # Return sorted list
    repos.sort
  end

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
      builds_by_day: {},
      total_builds: 0,
      average_build_duration: 0,
      deploys_by_day: {},
      total_deploys: 0,
      average_deploy_duration: 0,
      builds: {
        total: 0,
        success_rate: 0,
        avg_duration: 0
      },
      deployments: {
        total: 0,
        success_rate: 0,
        avg_duration: 0
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
end
