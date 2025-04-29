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
    end
  end
end
