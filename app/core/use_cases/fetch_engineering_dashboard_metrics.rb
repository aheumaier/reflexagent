# frozen_string_literal: true

module UseCases
  # FetchEngineeringDashboardMetrics aggregates all metrics needed for the main engineering dashboard
  class FetchEngineeringDashboardMetrics
    def initialize(storage_port:, cache_port: nil, logger_port: nil)
      @storage_port = storage_port
      @cache_port = cache_port
      @logger_port = logger_port
    end

    # @param time_period [Integer] The number of days to look back
    # @param filters [Hash] Optional filters to apply to metrics
    # @return [Hash] Complete dashboard metrics data
    def call(time_period:, filters: {})
      # Implementation will be added later
      {
        commit_metrics: default_commit_metrics,
        dora_metrics: default_dora_metrics,
        ci_cd_metrics: default_cicd_metrics,
        repo_metrics: default_repo_metrics,
        team_metrics: default_team_metrics,
        recent_alerts: []
      }
    end

    private

    # Default metrics to prevent UI errors
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

    # Default DORA metrics
    def default_dora_metrics
      {
        deployment_frequency: { value: 0, rating: "unknown", days_with_deployments: 0, total_days: 30,
                                total_deployments: 0 },
        lead_time: { value: 0, rating: "unknown", sample_size: 0 },
        time_to_restore: { value: 0, rating: "unknown", sample_size: 0 },
        change_failure_rate: { value: 0, rating: "unknown", failures: 0, deployments: 0 }
      }
    end

    # Default CI/CD metrics
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

    # Default repository metrics
    def default_repo_metrics
      {
        push_counts: {},
        active_repos: {},
        commit_volume: {},
        pr_metrics: { open: {}, closed: {}, merged: {} }
      }
    end

    # Default team metrics
    def default_team_metrics
      {
        top_contributors: {},
        team_velocity: 0,
        pr_review_time: 0
      }
    end
  end
end
