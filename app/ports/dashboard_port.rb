module DashboardPort
  # Fetch commit metrics for dashboard visualization
  # @param time_period [Integer] The number of days to look back
  # @param filters [Hash] Optional filters (like repository)
  # @return [Hash] Formatted commit metrics for display
  def get_commit_metrics(time_period:, filters: {})
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Fetch DORA metrics for dashboard visualization
  # @param time_period [Integer] The number of days to look back
  # @return [Hash] Formatted DORA metrics for display
  def get_dora_metrics(time_period:)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Fetch CI/CD metrics for dashboard visualization
  # @param time_period [Integer] The number of days to look back
  # @return [Hash] Formatted CI/CD metrics for display
  def get_cicd_metrics(time_period:)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Fetch repository metrics for dashboard visualization
  # @param time_period [Integer] The number of days to look back
  # @param limit [Integer] Maximum number of repositories to return
  # @return [Hash] Formatted repository metrics for display
  def get_repository_metrics(time_period:, limit: 5)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Fetch team metrics for dashboard visualization
  # @param time_period [Integer] The number of days to look back
  # @return [Hash] Formatted team metrics for display
  def get_team_metrics(time_period:)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Fetch recent alerts for dashboard display
  # @param time_period [Integer] The number of days to look back
  # @param limit [Integer] Maximum number of alerts to return
  # @param severity [String, nil] Optional severity filter
  # @return [Array<Hash>] Formatted alerts for display
  def get_recent_alerts(time_period:, limit: 5, severity: nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Fetch available repositories for filtering
  # @param time_period [Integer] The number of days to look back
  # @param limit [Integer] Maximum number of repositories to return
  # @return [Array<String>] List of repository names
  def get_available_repositories(time_period:, limit: 50)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Fetch detailed commit analysis for a specific repository
  # @param repository [String] Repository name to analyze
  # @param time_period [Integer] The number of days to look back
  # @return [Hash] Detailed commit analysis results
  def get_repository_commit_analysis(repository:, time_period:)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Fetch directory hotspots for a repository
  # @param repository [String, nil] Optional repository filter
  # @param time_period [Integer] The number of days to look back
  # @param limit [Integer] Maximum number of directories to return
  # @return [Array<Hash>] Directory hotspots with change counts
  def get_directory_hotspots(time_period:, repository: nil, limit: 10)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Fetch file extension hotspots for a repository
  # @param repository [String, nil] Optional repository filter
  # @param time_period [Integer] The number of days to look back
  # @param limit [Integer] Maximum number of file types to return
  # @return [Array<Hash>] File extension hotspots with change counts
  def get_file_extension_hotspots(time_period:, repository: nil, limit: 10)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Fetch commit type distribution for a repository
  # @param repository [String, nil] Optional repository filter
  # @param time_period [Integer] The number of days to look back
  # @param limit [Integer] Maximum number of commit types to return
  # @return [Array<Hash>] Commit types with counts and percentages
  def get_commit_type_distribution(time_period:, repository: nil, limit: 10)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Fetch author activity metrics for a repository
  # @param repository [String, nil] Optional repository filter
  # @param time_period [Integer] The number of days to look back
  # @param limit [Integer] Maximum number of authors to return
  # @return [Array<Hash>] Author activity data with commit counts and lines changed
  def get_author_activity(time_period:, repository: nil, limit: 10)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Fetch breaking changes metrics for a repository
  # @param repository [String, nil] Optional repository filter
  # @param time_period [Integer] The number of days to look back
  # @return [Hash] Breaking changes summary with author breakdown
  def get_breaking_changes(time_period:, repository: nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Fetch commit volume metrics for a repository
  # @param repository [String, nil] Optional repository filter
  # @param time_period [Integer] The number of days to look back
  # @return [Hash] Commit volume metrics with time series data
  def get_commit_volume(time_period:, repository: nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Fetch code churn metrics for a repository
  # @param repository [String, nil] Optional repository filter
  # @param time_period [Integer] The number of days to look back
  # @return [Hash] Code churn metrics (additions, deletions, churn ratio)
  def get_code_churn(time_period:, repository: nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Update dashboard with a new metric - real-time updates
  # @param metric [Domain::Metric] The metric to display on the dashboard
  # @return [Boolean] Success indicator
  def update_dashboard_with_metric(metric)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Update dashboard with a new alert - real-time updates
  # @param alert [Domain::Alert] The alert to display on the dashboard
  # @return [Boolean] Success indicator
  def update_dashboard_with_alert(alert)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end
end
