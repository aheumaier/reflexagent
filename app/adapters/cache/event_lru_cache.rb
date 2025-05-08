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
      event_data = redis_cache.read(cache_key(id_str))

      return nil unless event_data

      # Update access time to implement LRU behavior
      update_access_time(id_str)

      # Deserialize the event
      deserialize_event(event_data)
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

      # Evict if at capacity
      evict_if_needed

      # Store the event
      redis_cache.write(cache_key(id_str), serialize_event(event), ttl: ttl)

      # Update the index
      update_access_time(id_str)

      # Add to size tracking
      add_to_index(id_str)

      event
    rescue StandardError => e
      logger.error("Error caching event: #{e.message}")
      event
    end

    # Clear the entire cache
    #
    # @return [Boolean] true if successful
    def clear
      # Get all event keys
      index_key = cache_index_key

      # Delete all event entries and the index
      redis_cache.delete(index_key)
      redis_cache.clear("#{KEY_PREFIX}:*")

      true
    rescue StandardError => e
      logger.error("Error clearing event cache: #{e.message}")
      false
    end

    # Get the current cache size
    #
    # @return [Integer] Current number of items in cache
    def size
      redis_cache.read(cache_index_key)&.size || 0
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

    # Update access time for an event to implement LRU behavior
    #
    # @param id [String] Event ID
    def update_access_time(id)
      # Use current timestamp as score for LRU sorting
      Cache::RedisCache.with_redis(:cache) do |redis|
        redis.zadd(cache_index_key, Time.now.to_i, id)
      end
    end

    # Add event ID to the index
    #
    # @param id [String] Event ID
    def add_to_index(id)
      Cache::RedisCache.with_redis(:cache) do |redis|
        redis.zadd(cache_index_key, Time.now.to_i, id)
      end
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

        # Remove them from the cache
        oldest_items.each do |id|
          redis.del(cache_key(id))
        end

        # Remove them from the index
        redis.zremrangebyrank(cache_index_key, 0, evict_count - 1)
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
