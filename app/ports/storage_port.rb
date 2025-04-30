module Ports
  module StoragePort
    # Save an event to storage
    #
    # @param event [Core::Domain::Event] The event to save
    # @return [Core::Domain::Event] The saved event
    def save_event(event)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    # Find an event by ID
    #
    # @param id [String] The ID of the event to find
    # @return [Core::Domain::Event, nil] The event if found, nil otherwise
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
end
