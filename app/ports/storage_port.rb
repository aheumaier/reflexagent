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
end
