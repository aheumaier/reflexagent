module Adapters
  module Queue
    class ProcessEventWorker
      include Ports::QueuePort

      def enqueue_metric_calculation(event)
        # Use the MetricCalculationJob to process metrics asynchronously
        MetricCalculationJob.perform_later(event.id)
        true
      end

      def enqueue_anomaly_detection(metric)
        # In our updated flow, anomaly detection happens in the MetricCalculationJob
        # This method is kept for compatibility with the port interface
        true
      end
    end
  end
end
