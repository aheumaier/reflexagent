# frozen_string_literal: true

module Dashboard
  # DashboardAdapter implements the DashboardPort interface using various use cases
  # for fetching and formatting dashboard metrics
  class DashboardAdapter
    include DashboardPort

    def initialize(
      storage_port:,
      cache_port:,
      logger_port: nil,
      use_case_factory: UseCaseFactory
    )
      @storage_port = storage_port
      @cache_port = cache_port
      @logger_port = logger_port
      @use_case_factory = use_case_factory
    end

    # Fetch commit metrics for dashboard visualization
    # @param time_period [Integer] The number of days to look back
    # @param filters [Hash] Optional filters (like repository)
    # @return [Hash] Formatted commit metrics for display
    def get_commit_metrics(time_period:, filters: {})
      repository = filters[:repository]

      fetch_engineering_dashboard_metrics_use_case.call(
        time_period: time_period,
        filters: filters
      )[:commit_metrics]
    end

    # Fetch DORA metrics for dashboard visualization
    # @param time_period [Integer] The number of days to look back
    # @return [Hash] Formatted DORA metrics for display
    def get_dora_metrics(time_period:)
      {
        deployment_frequency: calculate_deployment_frequency_use_case.call(time_period: time_period),
        lead_time: calculate_lead_time_use_case.call(time_period: time_period),
        time_to_restore: calculate_time_to_restore_use_case.call(time_period: time_period),
        change_failure_rate: calculate_change_failure_rate_use_case.call(time_period: time_period)
      }
    end

    # Fetch CI/CD metrics for dashboard visualization
    # @param time_period [Integer] The number of days to look back
    # @param repository [String, nil] Optional repository filter
    # @return [Hash] Formatted CI/CD metrics for display
    def get_cicd_metrics(time_period:, repository: nil)
      builds_metrics = get_build_performance_metrics(time_period: time_period, repository: repository)
      deploy_metrics = get_deployment_performance_metrics(time_period: time_period, repository: repository)

      # Map to the expected structure in the view - directly use the fields from the use case response
      {
        builds: {
          total: builds_metrics[:total] || 0,
          success_rate: builds_metrics[:success_rate] || 0,
          avg_duration: builds_metrics[:avg_duration] || 0,
          builds_by_day: builds_metrics[:builds_by_day] || {},
          success_by_day: builds_metrics[:success_by_day] || {},
          builds_by_workflow: builds_metrics[:builds_by_workflow] || {},
          longest_workflow_durations: builds_metrics[:longest_workflow_durations] || {},
          flaky_builds: builds_metrics[:flaky_builds] || []
        },
        deployments: {
          total: deploy_metrics[:total] || 0,
          success_rate: deploy_metrics[:success_rate] || 0,
          avg_duration: deploy_metrics[:avg_duration] || 0,
          deployment_frequency: deploy_metrics[:deployment_frequency] || 0.0,
          deploys_by_day: deploy_metrics[:deploys_by_day] || {},
          success_rate_by_day: deploy_metrics[:success_rate_by_day] || {},
          deploys_by_workflow: deploy_metrics[:deploys_by_workflow] || {},
          durations_by_environment: deploy_metrics[:durations_by_environment] || {},
          common_failure_reasons: deploy_metrics[:common_failure_reasons] || {}
        }
      }
    end

    # Fetch repository metrics for dashboard visualization
    # @param time_period [Integer] The number of days to look back
    # @param limit [Integer] Maximum number of repositories to return
    # @return [Hash] Formatted repository metrics for display
    def get_repository_metrics(time_period:, limit: 5)
      # Initialize the structure that the view expects
      result = {
        push_counts: {},
        active_repos: {},
        commit_volume: {},
        pr_metrics: { open: {}, closed: {}, merged: {} }
      }

      # Add commit volume data first
      commit_volume_metrics = @storage_port.list_metrics(
        name: "github.commit_volume.daily",
        start_time: time_period.days.ago
      )

      # Format for the dashboard - group by date
      commit_volume_by_day = {}
      commit_volume_metrics.each do |metric|
        date = metric.dimensions["date"]
        commit_volume_by_day[date] = metric.value if date
      end

      # If no commit volume metrics found, try calculating from commit metrics
      if commit_volume_by_day.empty?
        commit_metrics = @storage_port.list_metrics(
          name: "github.push.commits",
          start_time: time_period.days.ago
        )

        # Group by day
        commit_metrics.group_by { |m| m.timestamp.strftime("%Y-%m-%d") }.each do |day, day_metrics|
          commit_volume_by_day[day] = day_metrics.sum(&:value)
        end
      end

      # Save the commit volume data
      result[:commit_volume] = commit_volume_by_day

      # First approach: Try to get active repositories from metrics
      # Get metrics that have repository dimension
      repo_metrics = @storage_port.list_metrics(
        name: "github.push.commits",
        start_time: time_period.days.ago
      )

      # Group by repository and count commits
      active_repos = {}
      repo_metrics.each do |metric|
        repo_name = metric.dimensions["repository"]
        next unless repo_name.present?

        active_repos[repo_name] ||= 0
        active_repos[repo_name] += metric.value.to_i
      end

      # If no repositories found through metrics, try getting them from the database
      if active_repos.empty?
        # Get all repositories from database
        repository_names = get_available_repositories(time_period: time_period, limit: limit)

        # Try to calculate commits for each known repository
        repository_names.each do |repository_name|
          commit_volume = calculate_commit_volume_use_case.call(
            time_period: time_period,
            repository: repository_name
          )

          # Add to active repos if there are commits
          commit_count = commit_volume[:total_commits] || 0
          active_repos[repository_name] = commit_count if commit_count > 0
        end
      end

      # If we still have no active repos but we have commit data, create a fallback entry
      if active_repos.empty? && !commit_volume_by_day.empty?
        active_repos["All Repositories"] = commit_volume_by_day.values.sum
      end

      # Sort by commit count descending and take top repositories
      result[:active_repos] = active_repos.sort_by { |_, count| -count }.to_h.first(limit).to_h

      # Log what we're returning
      @logger_port&.debug("Repository metrics prepared for view: #{result.inspect}")

      result
    end

    # Fetch team metrics for dashboard visualization
    # @param time_period [Integer] The number of days to look back
    # @return [Hash] Formatted team metrics for display
    def get_team_metrics(time_period:)
      fetch_engineering_dashboard_metrics_use_case.call(
        time_period: time_period
      )[:team_metrics]
    end

    # Fetch team performance metrics using the AnalyzeTeamPerformance use case
    # @param time_period [Integer] The number of days to look back
    # @param team_id [String, nil] Optional team identifier
    # @return [Hash] Comprehensive team performance metrics
    def get_team_performance_metrics(time_period:, team_id: nil)
      analyze_team_performance_use_case.get_team_performance_metrics(
        time_period: time_period,
        team_id: team_id
      )
    end

    # Fetch recent alerts for dashboard display
    # @param time_period [Integer] The number of days to look back
    # @param limit [Integer] Maximum number of alerts to return
    # @param severity [String, nil] Optional severity filter
    # @return [Array<Hash>] Formatted alerts for display
    def get_recent_alerts(time_period:, limit: 5, severity: nil)
      list_active_alerts_use_case.call(
        time_period: time_period,
        limit: limit,
        severity: severity
      )
    end

    # Fetch available repositories for filtering
    # @param time_period [Integer] The number of days to look back
    # @param limit [Integer] Maximum number of repositories to return
    # @param team_id [Integer, String] Optional team ID to filter repositories
    # @param team_slug [String] Optional team slug to filter repositories
    # @return [Array<String>] List of repository names
    def get_available_repositories(time_period:, limit: 50, team_id: nil, team_slug: nil)
      if team_id.present? || team_slug.present?
        # If a team identifier is provided, use the team-specific method
        get_team_repositories(team_id: team_id, team_slug: team_slug, limit: limit)
      else
        # Otherwise, get all repositories
        repositories = team_repository.list_repositories(limit: limit)
        repositories.map(&:name)
      end
    end

    # Fetch repositories for a specific team
    # @param team_id [Integer, String] The ID of the team
    # @param team_slug [String] Alternative to team_id - the slug of the team
    # @param limit [Integer] Maximum number of repositories to return
    # @param offset [Integer] Offset for pagination
    # @return [Array<String>] List of repository names for the team
    def get_team_repositories(team_id: nil, team_slug: nil, limit: 50, offset: 0)
      # Use the ListTeamRepositories use case to get repositories for a specific team
      repositories = list_team_repositories_use_case.call(
        team_id: team_id,
        team_slug: team_slug,
        limit: limit,
        offset: offset
      )

      # Only return repository names
      repositories.map(&:name)
    end

    # Fetch directory hotspots for a repository
    # @param repository [String, nil] Optional repository filter
    # @param time_period [Integer] The number of days to look back
    # @param limit [Integer] Maximum number of directories to return
    # @return [Array<Hash>] Directory hotspots with change counts
    def get_directory_hotspots(time_period:, repository: nil, limit: 10)
      identify_directory_hotspots_use_case.call(
        repository: repository,
        time_period: time_period,
        limit: limit
      )
    end

    # Fetch file extension hotspots for a repository
    # @param repository [String, nil] Optional repository filter
    # @param time_period [Integer] The number of days to look back
    # @param limit [Integer] Maximum number of file types to return
    # @return [Array<Hash>] File extension hotspots with change counts
    def get_file_extension_hotspots(time_period:, repository: nil, limit: 10)
      analyze_file_type_distribution_use_case.call(
        repository: repository,
        time_period: time_period,
        limit: limit
      )
    end

    # Fetch commit type distribution for a repository
    # @param repository [String, nil] Optional repository filter
    # @param time_period [Integer] The number of days to look back
    # @param limit [Integer] Maximum number of commit types to return
    # @return [Array<Hash>] Commit types with counts and percentages
    def get_commit_type_distribution(time_period:, repository: nil, limit: 10)
      classify_commit_types_use_case.call(
        repository: repository,
        time_period: time_period,
        limit: limit
      )
    end

    # Fetch author activity metrics for a repository
    # @param repository [String, nil] Optional repository filter
    # @param time_period [Integer] The number of days to look back
    # @param limit [Integer] Maximum number of authors to return
    # @return [Array<Hash>] Author activity data with commit counts and lines changed
    def get_author_activity(time_period:, repository: nil, limit: 10)
      track_author_activity_use_case.call(
        repository: repository,
        time_period: time_period,
        limit: limit
      )
    end

    # Fetch breaking changes metrics for a repository
    # @param repository [String, nil] Optional repository filter
    # @param time_period [Integer] The number of days to look back
    # @return [Hash] Breaking changes summary with author breakdown
    def get_breaking_changes(time_period:, repository: nil)
      detect_breaking_changes_use_case.call(
        repository: repository,
        time_period: time_period
      )
    end

    # Fetch commit volume metrics for a repository
    # @param repository [String, nil] Optional repository filter
    # @param time_period [Integer] The number of days to look back
    # @return [Hash] Commit volume metrics with time series data
    def get_commit_volume(time_period:, repository: nil)
      calculate_commit_volume_use_case.call(
        repository: repository,
        time_period: time_period
      )
    end

    # Fetch code churn metrics for a repository
    # @param repository [String, nil] Optional repository filter
    # @param time_period [Integer] The number of days to look back
    # @return [Hash] Code churn metrics (additions, deletions, churn ratio)
    def get_code_churn(time_period:, repository: nil)
      calculate_code_churn_use_case.call(
        repository: repository,
        time_period: time_period
      )
    end

    # Fetch detailed commit analysis for a specific repository
    # @param repository [String] Repository name to analyze
    # @param time_period [Integer] The number of days to look back
    # @return [Hash] Detailed commit analysis results
    def get_repository_commit_analysis(repository:, time_period:)
      {
        repository: repository,
        directory_hotspots: get_directory_hotspots(repository: repository, time_period: time_period),
        file_extension_hotspots: get_file_extension_hotspots(repository: repository, time_period: time_period),
        commit_types: get_commit_type_distribution(repository: repository, time_period: time_period),
        breaking_changes: get_breaking_changes(repository: repository, time_period: time_period),
        author_activity: get_author_activity(repository: repository, time_period: time_period),
        commit_volume: get_commit_volume(repository: repository, time_period: time_period),
        code_churn: get_code_churn(repository: repository, time_period: time_period)
      }
    end

    # Update dashboard with a new metric - real-time updates
    # @param metric [Domain::Metric] The metric to display on the dashboard
    # @return [Boolean] Success indicator
    def update_dashboard_with_metric(metric)
      # This would typically use a real-time mechanism like ActionCable/Hotwire
      # For now, just log the update
      @logger_port&.info("Dashboard updated with metric: #{metric.name}")
      true
    end

    # Update dashboard with a new alert - real-time updates
    # @param alert [Domain::Alert] The alert to display on the dashboard
    # @return [Boolean] Success indicator
    def update_dashboard_with_alert(alert)
      # This would typically use a real-time mechanism like ActionCable/Hotwire
      # For now, just log the update
      @logger_port&.info("Dashboard updated with alert: #{alert.name}")
      true
    end

    # Fetch build performance metrics directly
    # @param time_period [Integer] The number of days to look back
    # @param repository [String, nil] Optional repository filter
    # @return [Hash] Build performance metrics
    def get_build_performance_metrics(time_period:, repository: nil)
      # Create a direct instance of the metric repository instead of using DependencyContainer
      metric_repository = Repositories::MetricRepository.new(logger_port: @logger_port)

      # Create a direct instance of the use case with the metric repository
      use_case = UseCases::AnalyzeBuildPerformance.new(
        storage_port: metric_repository,
        cache_port: @cache_port,
        metric_naming_port: Adapters::Metrics::MetricNamingAdapter.new,
        logger_port: @logger_port
      )

      # Call the use case directly
      use_case.call(time_period: time_period, repository: repository)
    end

    # Fetch deployment performance metrics directly
    # @param time_period [Integer] The number of days to look back
    # @param repository [String, nil] Optional repository filter
    # @return [Hash] Deployment performance metrics
    def get_deployment_performance_metrics(time_period:, repository: nil)
      # Create a direct instance of the metric repository instead of using DependencyContainer
      metric_repository = Repositories::MetricRepository.new(logger_port: @logger_port)

      # Create a direct instance of the use case with the metric repository
      use_case = UseCases::AnalyzeDeploymentPerformance.new(
        storage_port: metric_repository,
        cache_port: @cache_port,
        metric_naming_port: Adapters::Metrics::MetricNamingAdapter.new,
        logger_port: @logger_port
      )

      # Call the use case directly
      use_case.call(time_period: time_period, repository: repository)
    end

    private

    # Factory methods for use cases
    def fetch_engineering_dashboard_metrics_use_case
      @fetch_engineering_dashboard_metrics_use_case ||= UseCases::FetchEngineeringDashboardMetrics.new(
        storage_port: @storage_port,
        cache_port: @cache_port,
        logger_port: @logger_port
      )
    end

    def calculate_deployment_frequency_use_case
      @calculate_deployment_frequency_use_case ||= UseCases::CalculateDeploymentFrequency.new(
        storage_port: @storage_port,
        logger_port: @logger_port
      )
    end

    def calculate_lead_time_use_case
      @calculate_lead_time_use_case ||= UseCases::CalculateLeadTime.new(
        storage_port: @storage_port,
        logger_port: @logger_port
      )
    end

    def calculate_time_to_restore_use_case
      @calculate_time_to_restore_use_case ||= UseCases::CalculateTimeToRestore.new(
        storage_port: @storage_port,
        logger_port: @logger_port
      )
    end

    def calculate_change_failure_rate_use_case
      @calculate_change_failure_rate_use_case ||= UseCases::CalculateChangeFailureRate.new(
        storage_port: @storage_port,
        logger_port: @logger_port
      )
    end

    def analyze_build_performance_use_case
      @analyze_build_performance_use_case ||= UseCases::AnalyzeBuildPerformance.new(
        storage_port: Repositories::MetricRepository.new(logger_port: @logger_port),
        cache_port: @cache_port,
        metric_naming_port: DependencyContainer.resolve(:metric_naming_port),
        logger_port: @logger_port
      )
    end

    def analyze_deployment_performance_use_case
      @analyze_deployment_performance_use_case ||= UseCases::AnalyzeDeploymentPerformance.new(
        storage_port: Repositories::MetricRepository.new(logger_port: @logger_port),
        cache_port: @cache_port,
        metric_naming_port: DependencyContainer.resolve(:metric_naming_port),
        logger_port: @logger_port
      )
    end

    def identify_directory_hotspots_use_case
      @identify_directory_hotspots_use_case ||= UseCases::IdentifyDirectoryHotspots.new(
        storage_port: @storage_port,
        cache_port: @cache_port
      )
    end

    def analyze_file_type_distribution_use_case
      @analyze_file_type_distribution_use_case ||= UseCases::AnalyzeFileTypeDistribution.new(
        storage_port: @storage_port,
        cache_port: @cache_port
      )
    end

    def classify_commit_types_use_case
      @classify_commit_types_use_case ||= UseCases::ClassifyCommitTypes.new(
        storage_port: @storage_port,
        cache_port: @cache_port
      )
    end

    def track_author_activity_use_case
      @track_author_activity_use_case ||= UseCases::TrackAuthorActivity.new(
        storage_port: @storage_port,
        cache_port: @cache_port
      )
    end

    def detect_breaking_changes_use_case
      @detect_breaking_changes_use_case ||= UseCases::DetectBreakingChanges.new(
        storage_port: @storage_port,
        cache_port: @cache_port
      )
    end

    def calculate_commit_volume_use_case
      @calculate_commit_volume_use_case ||= UseCases::CalculateCommitVolume.new(
        storage_port: @storage_port,
        cache_port: @cache_port
      )
    end

    def calculate_code_churn_use_case
      @calculate_code_churn_use_case ||= UseCases::CalculateCodeChurn.new(
        storage_port: @storage_port,
        cache_port: @cache_port
      )
    end

    def list_active_alerts_use_case
      @list_active_alerts_use_case ||= UseCases::ListActiveAlerts.new(
        storage_port: @storage_port,
        cache_port: @cache_port
      )
    end

    def team_repository
      @team_repository ||= DependencyContainer.resolve(:team_repository)
    end

    def list_team_repositories_use_case
      @list_team_repositories_use_case ||= UseCases::ListTeamRepositories.new(
        team_repository_port: team_repository,
        cache_port: @cache_port,
        logger_port: @logger_port
      )
    end

    def analyze_team_performance_use_case
      @analyze_team_performance_use_case ||= @use_case_factory.create_analyze_team_performance
    end
  end
end
