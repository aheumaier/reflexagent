module Core
  module UseCases
    class FindMetric
      def initialize(storage_port:)
        @storage_port = storage_port
      end

      def call(id)
        metric = @storage_port.find_metric(id)
        raise ArgumentError, "Metric with ID '#{id}' not found" if metric.nil?
        metric
      end
    end
  end
end
