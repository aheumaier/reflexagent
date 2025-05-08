# frozen_string_literal: true

module Cache
  # Redis-backed LRU cache for Domain::Event objects
  class EventLRUCache
    # Default TTL for cached events (1 hour)
    DEFAULT_TTL = 3600

    # Default cache size limit (1000 events)
    DEFAULT_MAX_SIZE = 1000

    # Redis key prefix for events
    KEY_PREFIX = "event_cache"

    attr_reader :logger, :redis_cache, :max_size

    # Initialize the LRU cache
    #
    # @param redis_cache [Cache::RedisCache] Redis cache adapter
    # @param max_size [Integer] Maximum number of items to cache
    # @param logger [Logger] Logger instance
    def initialize(redis_cache:, max_size: DEFAULT_MAX_SIZE, logger: nil)
      @redis_cache = redis_cache
      @max_size = max_size
      @logger = logger || Rails.logger
    end

    # Get an event from the cache
    #
    # @param id [String] Event ID
    # @return [Domain::Event, nil] The cached event or nil if not found
    def get(id)
      id_str = id.to_s

      # Use pipelining to get event data and update access time in a single Redis operation
      Cache::RedisCache.with_redis(:cache) do |redis|
        # Use pipelining to execute multiple commands in a single roundtrip
        results = redis.pipelined do |pipe|
          pipe.get(cache_key(id_str))
          pipe.zadd(cache_index_key, Time.now.to_i, id_str)
        end

        # Extract event data from pipeline results
        event_data = results[0]

        # Return nil if no event data found
        return nil unless event_data

        # Parse JSON data
        begin
          event_hash = JSON.parse(event_data)
          return deserialize_event(event_hash)
        rescue JSON::ParserError => e
          logger.error("Error parsing event data: #{e.message}")
          return nil
        end
      end
    rescue StandardError => e
      logger.error("Error retrieving event from cache: #{e.message}")
      nil
    end

    # Put an event in the cache
    #
    # @param event [Domain::Event] The event to cache
    # @param ttl [Integer] Time to live in seconds
    # @return [Domain::Event] The cached event
    def put(event, ttl: DEFAULT_TTL)
      id_str = event.id.to_s

      # Check if eviction is needed and perform it first
      evict_if_needed

      # Serialize the event data
      event_data = serialize_event(event).to_json
      current_time = Time.now.to_i

      # Use pipelining to store event data and update index in a single Redis operation
      Cache::RedisCache.with_redis(:cache) do |redis|
        redis.pipelined do |pipe|
          # Store the event with TTL
          pipe.setex(cache_key(id_str), ttl, event_data)

          # Update access time and index (these are the same operation for us)
          pipe.zadd(cache_index_key, current_time, id_str)
        end
      end

      event
    rescue StandardError => e
      logger.error("Error caching event: #{e.message}")
      event
    end

    # Clear the entire cache
    #
    # @return [Boolean] true if successful
    def clear
      # Get the index key
      index_key = cache_index_key

      # Get all event IDs from the index
      Cache::RedisCache.with_redis(:cache) do |redis|
        # Get all event IDs (for deletion)
        event_ids = redis.zrange(index_key, 0, -1)

        # If there are events to delete, use pipelining to delete them efficiently
        if event_ids.empty?
          # Just delete the index if there are no events
          redis.del(index_key)
        else
          redis.pipelined do |pipe|
            # Delete all event entries
            event_ids.each do |id|
              pipe.del(cache_key(id))
            end

            # Delete the index itself
            pipe.del(index_key)
          end
        end
      end

      true
    rescue StandardError => e
      logger.error("Error clearing event cache: #{e.message}")
      false
    end

    # Get the current cache size
    #
    # @return [Integer] Current number of items in cache
    def size
      Cache::RedisCache.with_redis(:cache) do |redis|
        redis.zcard(cache_index_key) || 0
      end
    rescue StandardError => e
      logger.error("Error getting cache size: #{e.message}")
      0
    end

    private

    # Generate a cache key for an event
    #
    # @param id [String] Event ID
    # @return [String] Cache key
    def cache_key(id)
      "#{KEY_PREFIX}:#{id}"
    end

    # Key for the sorted set that tracks LRU order
    #
    # @return [String] Cache index key
    def cache_index_key
      "#{KEY_PREFIX}:index"
    end

    # Evict oldest items if cache is at capacity
    def evict_if_needed
      current_size = size
      return unless current_size >= max_size

      # Calculate how many items to evict (remove oldest 10% when full)
      evict_count = [(current_size * 0.1).ceil, 1].max

      Cache::RedisCache.with_redis(:cache) do |redis|
        # Get the oldest items
        oldest_items = redis.zrange(cache_index_key, 0, evict_count - 1)

        # Use pipelining to efficiently remove items in a single Redis operation
        redis.pipelined do |pipe|
          # Delete all the event entries
          oldest_items.each do |id|
            pipe.del(cache_key(id))
          end

          # Remove them from the index in a single operation
          pipe.zremrangebyrank(cache_index_key, 0, evict_count - 1)
        end
      end

      logger.debug { "Evicted #{evict_count} items from event cache" }
    end

    # Serialize an event for storage
    #
    # @param event [Domain::Event] Event to serialize
    # @return [Hash] Serialized event data
    def serialize_event(event)
      event.to_h
    end

    # Deserialize event data into a Domain::Event
    #
    # @param data [Hash] Serialized event data
    # @return [Domain::Event] Deserialized event
    def deserialize_event(data)
      Domain::EventFactory.create(
        id: data["id"],
        name: data["name"],
        source: data["source"],
        data: data["data"],
        timestamp: Time.parse(data["timestamp"])
      )
    end
  end
end
