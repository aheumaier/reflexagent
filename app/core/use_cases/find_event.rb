module Core
  module UseCases
    class FindEvent
      def initialize(storage_port:)
        @storage_port = storage_port
      end

      def call(id)
        event = @storage_port.find_event(id)
        raise ArgumentError, "Event with ID '#{id}' not found" if event.nil?
        event
      end
    end
  end
end
