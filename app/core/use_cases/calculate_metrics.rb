module Core
  module UseCases
    class CalculateMetrics
      def initialize(storage_port:, cache_port:)
        @storage_port = storage_port
        @cache_port = cache_port
      end

      def call(event_id)
        event = @storage_port.find_event(event_id)
        return nil unless event

        # Generate an appropriate metric name based on the event name
        metric_name = if event.name.include?('cpu')
                        'cpu_usage'
                      else
                        "#{event.name}_count"
                      end

        # Extract a numeric value from the event data if present
        metric_value = if event.data.is_a?(Hash) && event.data[:value].is_a?(Numeric)
                         event.data[:value]
                       elsif event.data.is_a?(Hash) && event.data['value'].is_a?(Numeric)
                         event.data['value']
                       else
                         1 # Default value
                       end

        # Create dimensions from the event data, excluding the primary value
        dimensions = event.data.is_a?(Hash) ?
                     event.data.reject { |k, _| k.to_s == 'value' } :
                     {}

        # Create the metric
        metric = Core::Domain::Metric.new(
          name: metric_name,
          value: metric_value,
          source: event.source,
          dimensions: dimensions
        )

        @storage_port.save_metric(metric)
        @cache_port.cache_metric(metric)

        metric
      end
    end
  end
end
