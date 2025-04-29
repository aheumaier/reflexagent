module Adapters
  module Queue
    class ProcessEventWorker
      include Ports::QueuePort

      def enqueue_metric_calculation(event)
        # Implementation of QueuePort#enqueue_metric_calculation
        # Will enqueue a Sidekiq job in a real implementation
        true
      end

      def enqueue_anomaly_detection(metric)
        # Implementation of QueuePort#enqueue_anomaly_detection
        # Will enqueue a Sidekiq job in a real implementation
        true
      end
    end
  end
end
