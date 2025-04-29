module Core
  module UseCases
    class DetectAnomalies
      def initialize(storage_port:, notification_port:)
        @storage_port = storage_port
        @notification_port = notification_port
      end

      def call(metric_id)
        metric = @storage_port.find_metric(metric_id)

        # Simple placeholder anomaly detection logic
        if metric.value > 100
          alert = Core::Domain::Alert.new(
            name: "High #{metric.name}",
            severity: :warning,
            metric: metric,
            threshold: 100
          )

          @storage_port.save_alert(alert)
          @notification_port.send_alert(alert)

          return alert
        end

        nil
      end
    end
  end
end
