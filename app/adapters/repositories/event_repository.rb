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
        # Ensure event has an ID
        event = event.with_id(SecureRandom.uuid) if event.id.nil?

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
        # Create a record in the database
        record = DomainEvent.create!(
          aggregate_id: aggregate_id,
          event_type: event_type,
          payload: payload
        )

        # Convert to domain event
        domain_event = Core::Domain::Event.new(
          id: record.id,
          name: record.event_type,
          source: 'repository',  # Using 'repository' as the source since it's required
          timestamp: record.created_at,
          data: record.payload
        )

        # Store in memory as well if needed
        @events[domain_event.id] = domain_event

        domain_event
      end

      def read_events(from_position: 0, limit: nil)
        # Query the database
        query = DomainEvent.since_position(from_position).chronological
        query = query.limit(limit) if limit

        # Convert to domain events
        query.map do |record|
          Core::Domain::Event.new(
            id: record.id,
            name: record.event_type,
            source: 'repository',
            timestamp: record.created_at,
            data: record.payload
          )
        end
      end

      def read_stream(aggregate_id:, from_position: 0, limit: nil)
        # Query the database for events of a specific aggregate
        query = DomainEvent.for_aggregate(aggregate_id)
                           .since_position(from_position)
                           .chronological

        query = query.limit(limit) if limit

        # Convert to domain events
        query.map do |record|
          Core::Domain::Event.new(
            id: record.id,
            name: record.event_type,
            source: 'repository',
            timestamp: record.created_at,
            data: record.payload
          )
        end
      end

      # Metric operations
      def save_metric(metric)
        # Delegate to MetricRepository
        metric_repository.save_metric(metric)
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
        # Delegate to AlertRepository
        alert_repository.save_alert(alert)
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

      private

      def metric_repository
        @metric_repository ||= Adapters::Repositories::MetricRepository.new
      end

      def alert_repository
        @alert_repository ||= Adapters::Repositories::AlertRepository.new
      end
    end
  end
end
