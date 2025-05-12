# frozen_string_literal: true

require_relative "../../ports/storage_port"
require_relative "../../core/domain/event_factory"
require_relative "../cache/event_lru_cache"
require_relative "event_mapper"
require_relative "event_lookup_strategy"
require_relative "concerns/error_handler"

module Repositories
  # Database implementation of event storage using DomainEvent model
  class EventRepository
    include StoragePort
    include Repositories::Concerns::ErrorHandler

    require "securerandom"

    # Initialize the repository with dependencies
    #
    # @param cache_port [CachePort] Cache adapter (defaults to RedisCache)
    # @param event_mapper [EventMapper] Mapper for event transformations
    # @param logger_port [Logger] Logger instance
    def initialize(cache_port: nil, event_mapper: nil, logger_port: nil)
      @logger_port = logger_port || Rails.logger
      @event_mapper = event_mapper || EventMapper.new

      # For tests, use in-memory cache instead of Redis
      if Rails.env.test?
        @events_cache = {}
      else
        # Initialize Redis-backed LRU cache for production/development
        redis_cache = cache_port || Cache::RedisCache.new
        @events_cache = Cache::EventLRUCache.new(
          redis_cache: redis_cache,
          logger: @logger_port
        )
      end
    end

    # Save an event to the database
    #
    # @param event [Domain::Event] The event to save
    # @return [Domain::Event] The saved event
    def save_event(event)
      # Validate input
      raise ArgumentError, "Event cannot be nil" unless event

      context = {
        event_name: event.name,
        event_source: event.source,
        data_keys: event.data.keys
      }

      handle_database_error("save_event", context) do
        ActiveRecord::Base.transaction do
          # Map the domain event to database attributes
          attributes = @event_mapper.to_record_attributes(event)

          # Create a record in the database
          record = DomainEvent.new(attributes)
          record.save!

          # Create a new domain event with the database-generated ID
          new_event = Domain::EventFactory.create(
            id: record.id.to_s,
            name: event.name,
            source: event.source,
            data: event.data,
            timestamp: record.created_at
          )

          # Cache the event
          cache_event(new_event)

          @logger_port.debug { "Event persisted to database: #{new_event.id}, position: #{record.position}" }
          new_event
        end
      end
    end

    # Find an event by ID
    #
    # @param id [String, Integer, Hash] The ID of the event to find
    # @return [Domain::Event, nil] The event if found, nil otherwise
    def find_event(id)
      # Handle the case where a hash is passed
      id = id["id"] if id.is_a?(Hash) && id.key?("id")

      # Always convert to string for cache lookup
      id_str = id.to_s

      return nil if id_str.blank?

      context = { id: id_str }

      # Try to fetch from cache first
      cached_event = get_from_cache(id_str)
      return cached_event if cached_event

      handle_database_error("find_event", context) do
        # Use the appropriate lookup strategy based on ID format
        strategy = EventLookupStrategyFactory.for_id(id_str, @logger_port)
        record = strategy.find_record(id_str)

        # The repository's find_event method traditionally returns nil if not found
        # so we maintain that behavior rather than raising an error
        return nil unless record

        # Convert to domain event using the mapper
        domain_event = @event_mapper.to_domain_event(record)

        # Cache the event for future lookups
        cache_event(domain_event)

        @logger_port.debug { "Found event: #{domain_event.id} (#{domain_event.name})" }
        domain_event
      end
    end

    # Event store specific operations
    def append_event(aggregate_id:, event_type:, payload:)
      # Validate inputs
      raise ArgumentError, "Aggregate ID cannot be nil" unless aggregate_id
      raise ArgumentError, "Event type cannot be nil" unless event_type
      raise ArgumentError, "Payload cannot be nil" unless payload

      context = {
        aggregate_id: aggregate_id,
        event_type: event_type,
        payload_keys: payload.keys
      }

      handle_database_error("append_event", context) do
        ActiveRecord::Base.transaction do
          # Ensure we have a valid UUID for aggregate_id
          valid_aggregate_id = @event_mapper.event_id_to_aggregate_id(aggregate_id)

          # Create a record in the database
          record = DomainEvent.create!(
            aggregate_id: valid_aggregate_id,
            event_type: event_type,
            payload: payload
          )

          # Convert to domain event using the mapper
          domain_event = @event_mapper.to_domain_event(record)

          # Cache the event
          cache_event(domain_event)

          domain_event
        end
      end
    end

    def read_events(from_position: 0, limit: nil)
      context = {
        from_position: from_position,
        limit: limit
      }

      handle_query_error("read_events", context) do
        # Query the database
        query = DomainEvent.since_position(from_position).chronological
        query = query.limit(limit) if limit

        # Convert to domain events and cache them
        query.map do |record|
          # Check cache first
          event_id = record.id.to_s
          cached_event = get_from_cache(event_id)

          if cached_event
            cached_event
          else
            domain_event = @event_mapper.to_domain_event(record)
            cache_event(domain_event)
            domain_event
          end
        end
      end
    end

    def read_stream(aggregate_id:, from_position: 0, limit: nil)
      # Validate input
      raise ArgumentError, "Aggregate ID cannot be nil" unless aggregate_id

      context = {
        aggregate_id: aggregate_id,
        from_position: from_position,
        limit: limit
      }

      handle_query_error("read_stream", context) do
        # Query the database for events of a specific aggregate
        valid_aggregate_id = @event_mapper.event_id_to_aggregate_id(aggregate_id)

        query = DomainEvent.for_aggregate(valid_aggregate_id)
                           .since_position(from_position)
                           .chronological

        query = query.limit(limit) if limit

        # Convert to domain events and cache them
        query.map do |record|
          # Check cache first
          event_id = record.id.to_s
          cached_event = get_from_cache(event_id)

          if cached_event
            cached_event
          else
            domain_event = @event_mapper.to_domain_event(record)
            cache_event(domain_event)
            domain_event
          end
        end
      end
    end

    private

    # Cache an event, using the appropriate caching mechanism based on environment
    def cache_event(event)
      return nil unless event

      begin
        if Rails.env.test?
          # Use in-memory cache for tests
          @events_cache[event.id.to_s] = event
        else
          # Use Redis LRU cache for production/development
          @events_cache.put(event)
        end
      rescue StandardError => e
        # Log the error but don't fail the operation if caching fails
        log_error("Failed to cache event: #{event.id}", e)
        nil
      end

      event
    end

    # Get an event from cache, using the appropriate caching mechanism based on environment
    def get_from_cache(id)
      return nil unless id.present?

      begin
        if Rails.env.test?
          # Use in-memory cache for tests
          @events_cache[id]
        else
          # Use Redis LRU cache for production/development
          @events_cache.get(id)
        end
      rescue StandardError => e
        # Log the error but don't fail the operation if cache retrieval fails
        log_error("Failed to retrieve event from cache: #{id}", e)
        nil
      end
    end
  end
end
