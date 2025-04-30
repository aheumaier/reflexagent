module Adapters
  module Repositories
    class MetricRepository
      def initialize
        @metrics = {}
      end

      def save_metric(metric)
        # In a real implementation, this would save to a database
        # For our test, we'll just store in memory
        @metrics[metric.id] = metric
        metric
      end

      def find_metric(id)
        # In a real implementation, this would query the database
        # For our test, we'll just fetch from memory
        @metrics[id]
      end

      def list_metrics(filters = {})
        # In a real implementation, this would query the database with filters
        # For our test, we'll just return all metrics
        @metrics.values
      end
    end
  end
end
