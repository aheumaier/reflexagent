# frozen_string_literal: true

module Domain
  # Factory class for creating Domain::Event objects with consistent parameters
  # This provides a standardized interface for event creation across the application
  class EventFactory
    # Create a new Domain::Event with standardized parameter naming
    #
    # @param name [String] The name/type of the event (maps to event_type in database)
    # @param source [String] The source system that generated the event (maps to aggregate_id in database)
    # @param data [Hash] The event payload data (maps to payload in database)
    # @param id [String, nil] Optional ID for the event (will be auto-generated if not provided)
    # @param timestamp [Time] When the event occurred (maps to created_at in database)
    # @return [Domain::Event] A new Domain::Event instance
    def self.create(name:, source:, data:, id: nil, timestamp: Time.current)
      Domain::Event.new(
        name: name,
        source: source,
        data: data,
        id: id,
        timestamp: timestamp
      )
    end

    # Create a Domain::Event from a DomainEvent ActiveRecord object
    # This standardizes the mapping between database columns and domain attributes
    #
    # @param record [DomainEvent] The database record to convert
    # @return [Domain::Event] A new Domain::Event instance
    def self.from_record(record)
      Domain::Event.new(
        id: record.id.to_s,
        name: record.event_type,
        source: record.aggregate_id,
        data: record.payload,
        timestamp: record.created_at
      )
    end

    # Prepare a Domain::Event for persistence to database
    # This maps domain attributes to their database column equivalents
    #
    # @param event [Domain::Event] The domain event to prepare for persistence
    # @return [Hash] A hash of attributes ready for database persistence
    def self.to_persistence_attributes(event)
      {
        aggregate_id: event.source,
        event_type: event.name,
        payload: event.data
        # id and timestamp/created_at are typically handled by the database
      }
    end
  end
end
