module Ports
  module QueuePort
    def enqueue_metric_calculation(event)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def enqueue_anomaly_detection(metric)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end
  end
end
