# frozen_string_literal: true

require "securerandom"
module Domain
  # Event represents a domain event in the system
  class Event
    attr_reader :id, :name, :source, :data, :timestamp

    # Create a new Event
    #
    # @param id [String, nil] Optional ID for the event (will be auto-generated if not provided)
    # @param name [String] The name/type of the event
    # @param source [String] The source system that generated the event
    # @param data [Hash] The event payload data
    # @param timestamp [Time] When the event occurred
    def initialize(name:, source:, data:, id: nil, timestamp: Time.current)
      @id = id || SecureRandom.uuid
      @name = name
      @source = source
      @data = data
      @timestamp = timestamp
      validate!
    end

    # Convert the event to a hash for serialization
    #
    # @return [Hash] The event as a hash
    def to_h
      {
        id: id,
        name: name,
        source: source,
        data: data,
        timestamp: timestamp.iso8601
      }
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

    def with_id(new_id)
      self.class.new(
        id: new_id,
        name: name,
        source: source,
        data: data.dup,
        timestamp: timestamp
      )
    end

    private

    # Validates that the event data is well-formed
    # @raise [ArgumentError] If any validations fail
    def validate!
      raise ArgumentError, "Event name cannot be blank" if name.nil? || name.strip.empty?
      raise ArgumentError, "Event source cannot be blank" if source.nil? || source.strip.empty?
      raise ArgumentError, "Event data must be a Hash" unless data.is_a?(Hash)
      raise ArgumentError, "Event timestamp must be a Time" unless timestamp.is_a?(Time)
    end
  end
end
