module Adapters
  module Repositories
    class EventRepository
      include Ports::StoragePort

      def save_event(event)
        # Implementation of StoragePort#save_event
        # Will save to the database in a real implementation
        event
      end

      def find_event(id)
        # Implementation of StoragePort#find_event
        # Will query the database in a real implementation
        nil
      end

      # Other StoragePort methods will be implemented by other repositories
      def save_metric(metric)
        Adapters::Repositories::MetricRepository.new.save_metric(metric)
      end

      def find_metric(id)
        Adapters::Repositories::MetricRepository.new.find_metric(id)
      end

      def list_metrics(filters = {})
        Adapters::Repositories::MetricRepository.new.list_metrics(filters)
      end

      def save_alert(alert)
        Adapters::Repositories::AlertRepository.new.save_alert(alert)
      end

      def find_alert(id)
        Adapters::Repositories::AlertRepository.new.find_alert(id)
      end

      def list_alerts(filters = {})
        Adapters::Repositories::AlertRepository.new.list_alerts(filters)
      end
    end
  end
end
