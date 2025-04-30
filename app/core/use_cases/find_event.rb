module Core
  module UseCases
    # FindEvent use case retrieves an event from the storage port
    class FindEvent
      def initialize(storage_port:)
        @storage_port = storage_port
      end

      # Find an event by its ID
      #
      # @param id [String] The ID of the event to find
      # @return [Core::Domain::Event, nil] The event if found, nil otherwise
      def call(id)
        @storage_port.find_event(id)
      end
    end
  end
end
