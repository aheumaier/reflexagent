module StoragePort
  # Save an event to storage
  #
  # @param event [Domain::Event] The event to save
  # @return [Domain::Event] The saved event
  def save_event(event)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Find an event by ID
  #
  # @param id [String] The ID of the event to find
  # @return [Domain::Event, nil] The event if found, nil otherwise
  def find_event(id)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Event store specific operations
  def append_event(aggregate_id:, event_type:, payload:)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def read_events(from_position: 0, limit: nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def read_stream(aggregate_id:, from_position: 0, limit: nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Metric operations
  def save_metric(metric)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def find_metric(id)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def list_metrics(filters = {})
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # List metrics that match a given name pattern (using SQL LIKE syntax)
  # @param pattern [String] The pattern to match against metric names (using % as wildcard)
  # @param start_time [Time, nil] Optional start time filter
  # @param end_time [Time, nil] Optional end time filter
  # @return [Array<Domain::Metric>] List of matching metrics
  def list_metrics_with_name_pattern(pattern, start_time: nil, end_time: nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Find an aggregate metric by name and dimensions
  def find_aggregate_metric(name, dimensions)
    raise NotImplementedError
  end

  # Update an existing metric (for aggregates)
  def update_metric(metric)
    raise NotImplementedError
  end

  # Metric analytics operations
  def get_average(name, start_time = nil, end_time = nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def get_percentile(name, percentile, start_time = nil, end_time = nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Alert operations
  def save_alert(alert)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def find_alert(id)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def list_alerts(filters = {})
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Commit metrics analysis operations

  # Find hotspot directories for the given time period
  # @param since [Time] The start time for analysis
  # @param repository [String, nil] Optional repository filter
  # @param limit [Integer] Maximum number of results to return
  # @return [Array<Hash>] Array of directory hotspots with counts
  def hotspot_directories(since:, repository: nil, limit: 10)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Find hotspot file types for the given time period
  # @param since [Time] The start time for analysis
  # @param repository [String, nil] Optional repository filter
  # @param limit [Integer] Maximum number of results to return
  # @return [Array<Hash>] Array of file type hotspots with counts
  def hotspot_filetypes(since:, repository: nil, limit: 10)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Find distribution of commit types for the given time period
  # @param since [Time] The start time for analysis
  # @param repository [String, nil] Optional repository filter
  # @return [Array<Hash>] Array of commit types with counts
  def commit_type_distribution(since:, repository: nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Find most active authors for the given time period
  # @param since [Time] The start time for analysis
  # @param repository [String, nil] Optional repository filter
  # @param limit [Integer] Maximum number of results to return
  # @return [Array<Hash>] Array of authors with commit counts
  def author_activity(since:, repository: nil, limit: 10)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Find lines changed by author for the given time period
  # @param since [Time] The start time for analysis
  # @param repository [String, nil] Optional repository filter
  # @return [Array<Hash>] Array of authors with lines added/removed
  def lines_changed_by_author(since:, repository: nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Find breaking changes by author for the given time period
  # @param since [Time] The start time for analysis
  # @param repository [String, nil] Optional repository filter
  # @return [Array<Hash>] Array of authors with breaking change counts
  def breaking_changes_by_author(since:, repository: nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Find commit activity by day for the given time period
  # @param since [Time] The start time for analysis
  # @param repository [String, nil] Optional repository filter
  # @return [Array<Hash>] Array of days with commit counts
  def commit_activity_by_day(since:, repository: nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Get active repositories with optimized DB-level aggregation
  # @param start_time [Time] The start time for filtering activity
  # @param limit [Integer] Maximum number of repositories to return
  # @param page [Integer] Page number for pagination
  # @param per_page [Integer] Items per page for pagination
  # @return [Array<String>] List of repository names
  def get_active_repositories(start_time:, limit: 50, page: nil, per_page: nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end
end
