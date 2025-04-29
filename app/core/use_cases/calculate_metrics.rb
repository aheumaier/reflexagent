module Core
  module UseCases
    class CalculateMetrics
      def initialize(storage_port:, cache_port:)
        @storage_port = storage_port
        @cache_port = cache_port
      end

      def call(event_id)
        event = @storage_port.find_event(event_id)
        # Simple placeholder - in a real implementation, this would have more logic
        metric = Core::Domain::Metric.new(
          name: "#{event.name}_count",
          value: 1,
          source: event.source,
          dimensions: event.data
        )

        @storage_port.save_metric(metric)
        @cache_port.cache_metric(metric)

        metric
      end
    end
  end
end
