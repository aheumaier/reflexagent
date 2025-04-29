module Adapters
  module Repositories
    class MetricRepository
      def save_metric(metric)
        # Implementation of StoragePort#save_metric
        # Will save to the database in a real implementation
        metric
      end

      def find_metric(id)
        # Implementation of StoragePort#find_metric
        # Will query the database in a real implementation
        nil
      end
    end
  end
end
