# frozen_string_literal: true

module Domain
  class Metric
    attr_reader :id, :name, :value, :timestamp, :source, :dimensions

    def initialize(name:, value:, source:, id: nil, timestamp: Time.now, dimensions: {})
      @id = id
      @name = name
      @value = value
      @timestamp = timestamp
      @source = source
      @dimensions = dimensions
      validate!
    end

    # Validation methods
    def valid?
      name.present? &&
        !value.nil? &&
        !source.nil? && !source.empty? &&
        timestamp.is_a?(Time) &&
        dimensions.is_a?(Hash)
    end

    def validate!
      raise ArgumentError, "Name cannot be empty" if name.nil? || name.empty?
      raise ArgumentError, "Value cannot be nil" if value.nil?
      raise ArgumentError, "Source cannot be empty" if source.nil? || source.empty?
      raise ArgumentError, "Timestamp must be a Time object" unless timestamp.is_a?(Time)
      raise ArgumentError, "Dimensions must be a hash" unless dimensions.is_a?(Hash)
    end

    # Equality methods for testing
    def ==(other)
      return false unless other.is_a?(Metric)

      id == other.id &&
        name == other.name &&
        value == other.value &&
        source == other.source &&
        timestamp.to_i == other.timestamp.to_i &&
        dimensions == other.dimensions
    end

    alias eql? ==

    def hash
      [id, name, value, source, timestamp.to_i, dimensions].hash
    end

    # Business logic methods
    def numeric?
      value.is_a?(Numeric)
    end

    def age
      Time.now - timestamp
    end

    def to_h
      {
        id: id,
        name: name,
        value: value,
        timestamp: timestamp,
        source: source,
        dimensions: dimensions
      }
    end

    def with_id(new_id)
      self.class.new(
        id: new_id,
        name: name,
        value: value,
        timestamp: timestamp,
        source: source,
        dimensions: dimensions.dup
      )
    end

    def with_value(new_value)
      self.class.new(
        id: id,
        name: name,
        value: new_value,
        timestamp: timestamp,
        source: source,
        dimensions: dimensions.dup
      )
    end
  end
end
