module UseCases
  # FindEvent use case retrieves an event from the storage port
  class FindEvent
    def initialize(storage_port:)
      @storage_port = storage_port
    end

    # Find an event by its ID
    #
    # @param id [String] The ID of the event to find
    # @return [Domain::Event] The event if found
    # @raise [ArgumentError] If the event is not found
    def call(id)
      event = @storage_port.find_event(id)

      raise ArgumentError, "Event with ID '#{id}' not found" if event.nil?

      event
    end
  end
end
