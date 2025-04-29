module Core
  module Domain
    class Alert
      attr_reader :id, :name, :severity, :metric, :threshold, :timestamp, :status

      SEVERITIES = [:info, :warning, :critical].freeze
      STATUSES = [:active, :acknowledged, :resolved].freeze

      def initialize(id: nil, name:, severity:, metric:, threshold:, timestamp: Time.now, status: :active)
        @id = id
        @name = name
        @severity = severity
        @metric = metric
        @threshold = threshold
        @timestamp = timestamp
        @status = status
      end

      def message
        "#{name} - #{metric.name} exceeded threshold of #{threshold}"
      end

      def details
        {
          metric_name: metric.name,
          metric_value: metric.value,
          threshold: threshold,
          source: metric.source,
          dimensions: metric.dimensions
        }
      end

      def created_at
        timestamp
      end
    end
  end
end
