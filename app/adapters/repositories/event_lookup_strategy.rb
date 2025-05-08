# frozen_string_literal: true

module Repositories
  # Base class for event lookup strategies
  class EventLookupStrategy
    attr_reader :logger

    def initialize(logger)
      @logger = logger
    end

    def find_record(_id_str)
      raise NotImplementedError, "Subclasses must implement find_record"
    end
  end

  # Strategy for looking up by UUID (aggregate_id)
  class UuidLookupStrategy < EventLookupStrategy
    def find_record(id_str)
      logger.debug { "Looking up event by UUID: #{id_str}" }
      DomainEvent.find_by(aggregate_id: id_str)
    end
  end

  # Strategy for looking up by numeric ID
  class NumericIdLookupStrategy < EventLookupStrategy
    def find_record(id_str)
      logger.debug { "Looking up event by numeric ID: #{id_str}" }
      DomainEvent.find_by(id: id_str.to_i)
    end
  end

  # Fallback strategy that tries multiple approaches
  class FallbackLookupStrategy < EventLookupStrategy
    def find_record(id_str)
      logger.debug { "Looking up event by ID (mixed strategy): #{id_str}" }
      record = DomainEvent.find_by(id: id_str)
      record ||= DomainEvent.find_by(aggregate_id: id_str)

      # Last resort: scan all events if first two approaches failed
      unless record
        DomainEvent.all.each do |evt|
          if evt.id.to_s == id_str
            record = evt
            break
          end
        end
      end

      record
    end
  end

  # Factory that determines which lookup strategy to use
  class EventLookupStrategyFactory
    def self.for_id(id_str, logger)
      uuid_regex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

      if uuid_regex.match?(id_str)
        UuidLookupStrategy.new(logger)
      elsif id_str.match?(/^\d+$/)
        NumericIdLookupStrategy.new(logger)
      else
        FallbackLookupStrategy.new(logger)
      end
    end
  end
end
