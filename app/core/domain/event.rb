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
        validate!
      end

      # Validation methods
      def valid?
        !name.nil? && !name.empty? && !source.nil? && !source.empty? && timestamp.is_a?(Time)
      end

      def validate!
        raise ArgumentError, "Name cannot be empty" if name.nil? || name.empty?
        raise ArgumentError, "Source cannot be empty" if source.nil? || source.empty?
        raise ArgumentError, "Timestamp must be a Time object" unless timestamp.is_a?(Time)
        raise ArgumentError, "Data must be a hash" unless data.is_a?(Hash)
      end

      # Equality methods for testing
      def ==(other)
        return false unless other.is_a?(Event)
        id == other.id &&
          name == other.name &&
          source == other.source &&
          timestamp.to_i == other.timestamp.to_i &&
          data == other.data
      end

      alias eql? ==

      def hash
        [id, name, source, timestamp.to_i, data].hash
      end

      # Business logic methods
      def age
        Time.now - timestamp
      end

      def to_h
        {
          id: id,
          name: name,
          source: source,
          timestamp: timestamp,
          data: data
        }
      end

      def with_id(new_id)
        self.class.new(
          id: new_id,
          name: name,
          source: source,
          timestamp: timestamp,
          data: data.dup
        )
      end
    end
  end
end
