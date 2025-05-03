module UseCases
  class ProcessEvent
    def initialize(ingestion_port:, storage_port:, queue_port:)
      @ingestion_port = ingestion_port
      @storage_port = storage_port
      @queue_port = queue_port
    end

    # Process a raw webhook payload
    # @param raw_payload [String] The raw JSON webhook payload
    # @param source [String] The source of the webhook (github, jira, etc.)
    # @return [Core::Domain::Event] The processed domain event
    def call(raw_payload, source:)
      Rails.logger.debug { "ProcessEvent.call starting for #{source} event" }

      # Parse the raw payload into a domain event
      begin
        event = @ingestion_port.receive_event(raw_payload, source: source)
        Rails.logger.debug { "Event parsed: #{event.id} (#{event.name})" }
      rescue StandardError => e
        Rails.logger.error("Error parsing event: #{e.message}")
        raise EventParsingError, "Failed to parse event: #{e.message}"
      end

      # Store the event in the repository
      begin
        stored_event = @storage_port.save_event(event)
        event = stored_event
        Rails.logger.debug { "Event saved: #{event.id}" }
      rescue StandardError => e
        Rails.logger.error("Error saving event: #{e.message}")
        raise EventStorageError, "Failed to save event: #{e.message}"
      end

      # Enqueue for async metric calculation
      begin
        @queue_port.enqueue_metric_calculation(event)
        Rails.logger.debug { "Event enqueued for metric calculation: #{event.id}" }
      rescue StandardError => e
        Rails.logger.error("Error enqueuing event: #{e.message}")
        # We don't want to fail the whole process if enqueueing fails
        # The event is already stored, so it can be recovered later
        Rails.logger.error("Continuing despite enqueueing error")
      end

      # Return the processed event
      event
    end

    # Custom error classes for clearer exception handling
    class EventParsingError < StandardError; end
    class EventStorageError < StandardError; end
  end
end
