# frozen_string_literal: true

module Repositories
  # EventMapper class handles the transformation between domain events and database records
  class EventMapper
    require "securerandom"

    # Transform a domain event to a database record
    #
    # @param event [Domain::Event] The domain event to transform
    # @return [Hash] Attributes to create a database record
    def to_record_attributes(event)
      {
        aggregate_id: event_id_to_aggregate_id(event.source),
        event_type: event.name,
        payload: event.data
      }
    end

    # Transform a database record to a domain event
    #
    # @param record [DomainEvent] The database record to transform
    # @return [Domain::Event] A domain event
    def to_domain_event(record)
      Domain::EventFactory.create(
        id: record.id.to_s,
        name: record.event_type,
        source: record.aggregate_id,
        data: record.payload,
        timestamp: record.created_at
      )
    end

    # Transform a valid id to a storable aggregate_id
    #
    # @param source [String] Source identifier which may not be a valid UUID
    # @return [String] A valid UUID
    def event_id_to_aggregate_id(source)
      valid_uuid?(source) ? source : generate_uuid_from_string(source)
    end

    private

    # Check if a string is a valid UUID
    #
    # @param string [String] String to check
    # @return [Boolean] True if valid UUID, false otherwise
    def valid_uuid?(string)
      uuid_regex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      uuid_regex.match?(string.to_s)
    end

    # Generate a UUID from a string
    #
    # @param string [String] String to generate UUID from
    # @return [String] A valid UUID
    def generate_uuid_from_string(string)
      # In a production system, you might want to use a more deterministic approach
      # such as a namespace UUID (v5) if available
      SecureRandom.uuid
    end
  end
end
