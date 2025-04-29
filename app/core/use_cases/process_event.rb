module Core
  module UseCases
    class ProcessEvent
      def initialize(storage_port:, queue_port:)
        @storage_port = storage_port
        @queue_port = queue_port
      end

      def call(event)
        @storage_port.save_event(event)
        @queue_port.enqueue_metric_calculation(event)
      end
    end
  end
end
