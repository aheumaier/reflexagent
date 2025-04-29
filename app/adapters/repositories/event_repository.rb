module Adapters
  module Repositories
    class EventRepository
      include Ports::StoragePort

      # Basic event operations
      def save_event(event)
        # Convert Domain::Event to EventStore format
        stored_event = append_event(
          aggregate_id: event.id || SecureRandom.uuid,
          event_type: event.name,
          payload: event.data
        )

        # If the event didn't have an ID before, assign the ID from the stored event
        event.id.nil? ? event.with_id(stored_event.id) : event
      end

      def find_event(id)
        # Read all events and find the specific one by ID
        read_events.find { |event| event.id.to_s == id.to_s }
      end

      # Event store specific operations
      def append_event(aggregate_id:, event_type:, payload:)
        event_record = DomainEvent.create!(
          aggregate_id: aggregate_id,
          event_type: event_type,
          payload: payload
        )
        map_record_to_event(event_record)
      end

      def read_events(from_position: 0, limit: nil)
        scope = DomainEvent.since_position(from_position).chronological
        scope = scope.limit(limit) if limit
        scope.map { |record| map_record_to_event(record) }
      end

      def read_stream(aggregate_id:, from_position: 0, limit: nil)
        scope = DomainEvent.for_aggregate(aggregate_id)
                           .since_position(from_position)
                           .chronological
        scope = scope.limit(limit) if limit
        scope.map { |record| map_record_to_event(record) }
      end

      # Metric operations - delegated to MetricRepository
      def save_metric(metric)
        Adapters::Repositories::MetricRepository.new.save_metric(metric)
      end

      def find_metric(id)
        Adapters::Repositories::MetricRepository.new.find_metric(id)
      end

      def list_metrics(filters = {})
        Adapters::Repositories::MetricRepository.new.list_metrics(filters)
      end

      # Alert operations - delegated to AlertRepository
      def save_alert(alert)
        Adapters::Repositories::AlertRepository.new.save_alert(alert)
      end

      def find_alert(id)
        Adapters::Repositories::AlertRepository.new.find_alert(id)
      end

      def list_alerts(filters = {})
        Adapters::Repositories::AlertRepository.new.list_alerts(filters)
      end

      private

      def map_record_to_event(record)
        Core::Domain::Event.new(
          id: record.id,
          name: record.event_type,
          source: 'event_store',
          timestamp: record.created_at,
          data: record.payload
        )
      end
    end
  end
end
