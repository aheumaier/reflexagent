module Core
  module Domain
    class Metric
      attr_reader :id, :name, :value, :timestamp, :source, :dimensions

      def initialize(id: nil, name:, value:, timestamp: Time.now, source:, dimensions: {})
        @id = id
        @name = name
        @value = value
        @timestamp = timestamp
        @source = source
        @dimensions = dimensions
      end
    end
  end
end
