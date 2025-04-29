module Ports
  module StoragePort
    def save_event(event)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def find_event(id)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def save_metric(metric)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def find_metric(id)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def save_alert(alert)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def find_alert(id)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end
  end
end
