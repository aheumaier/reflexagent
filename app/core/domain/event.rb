module Core
  module Domain
    class Event
      attr_reader :id, :name, :source, :timestamp, :data

      def initialize(id: nil, name:, source:, timestamp: Time.now, data: {})
        @id = id
        @name = name
        @source = source
        @timestamp = timestamp
        @data = data
      end
    end
  end
end
