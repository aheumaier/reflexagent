module Adapters
  module Repositories
    class EventRepository
      include Ports::StoragePort

      def initialize
        @events = {}
        @metrics = {}
        @alerts = {}
      end

      # Basic event operations
      def save_event(event)
        # In a real implementation, this would save to a database
        # For our test, we'll just store in memory
        @events[event.id] = event
        event
      end

      def find_event(id)
        # In a real implementation, this would query the database
        # For our test, we'll just fetch from memory
        @events[id]
      end

      # Event store specific operations
      def append_event(aggregate_id:, event_type:, payload:)
        # Not implemented for this test
        true
      end

      def read_events(from_position: 0, limit: nil)
        # Return all events for now
        @events.values
      end

      def read_stream(aggregate_id:, from_position: 0, limit: nil)
        # Not implemented for this test
        []
      end

      # Metric operations
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

      # Alert operations
      def save_alert(alert)
        # In a real implementation, this would save to a database
        # For our test, we'll just store in memory
        @alerts[alert.id] = alert
        alert
      end

      def find_alert(id)
        # In a real implementation, this would query the database
        # For our test, we'll just fetch from memory
        @alerts[id]
      end

      def list_alerts(filters = {})
        # In a real implementation, this would query the database with filters
        # For our test, we'll just return all alerts
        @alerts.values
      end
    end
  end
end
