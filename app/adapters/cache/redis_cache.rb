# frozen_string_literal: true

require_relative "../../ports/cache_port"
module Cache
  class RedisCache
    include CachePort

    # Class-level connection pool cache
    class_attribute :connection_pool_cache, default: {}

    # Default expiration time of 1 hour if not specified
    DEFAULT_TTL = 3600

    # Redis connection management
    def self.redis
      @redis ||= Redis.new(
        url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
        reconnect_attempts: 3
      )
    end

    # Helper method to execute a block with a Redis connection
    def self.with_redis(purpose = :default, &)
      if defined?(ConnectionPool) && block_given?
        connection_pool_for(purpose).with(&)
      else
        yield redis
      end
    end

    # Configure ConnectionPool size and timeout from ENV
    def self.connection_pool_size
      ENV.fetch("REDIS_POOL_SIZE", 10).to_i
    end

    def self.connection_pool_timeout
      ENV.fetch("REDIS_POOL_TIMEOUT", 5).to_i
    end

    # Return the URL for a Redis DB for a given purpose
    def self.url_for(purpose = :default)
      case purpose.to_sym
      when :cache then ENV.fetch("REDIS_CACHE_URL") { ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
      when :queue then ENV.fetch("REDIS_QUEUE_URL") { ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
      when :throttling then ENV.fetch("REDIS_THROTTLING_URL") { ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
      else ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
      end
    end

    # Build a new connection pool
    def self.build_connection_pool(purpose)
      require "connection_pool" unless defined?(ConnectionPool)

      ConnectionPool.new(size: connection_pool_size, timeout: connection_pool_timeout) do
        client = Redis.new(
          url: url_for(purpose),
          timeout: ENV.fetch("REDIS_TIMEOUT", 5).to_i,
          reconnect_attempts: ENV.fetch("REDIS_RECONNECT_ATTEMPTS", 3).to_i
        )

        # Run a quick test to ensure the connection works in development
        if Rails.env.development?
          begin
            client.ping
            Rails.logger.info("Redis connection successful: #{url_for(purpose)}")
          rescue Redis::BaseError => e
            Rails.logger.error("Redis connection failed: #{e.message}")
          end
        end

        client
      end
    end

    # Find or build a connection pool
    def self.find_or_build_connection_pool(purpose)
      connection_pool_cache[purpose] ||= build_connection_pool(purpose)
    end

    # Return a memoized ConnectionPool instance for a given purpose
    def self.connection_pool_for(purpose = :default)
      case purpose.to_sym
      when :cache then find_or_build_connection_pool(:cache)
      when :queue then find_or_build_connection_pool(:queue)
      when :throttling then find_or_build_connection_pool(:throttling)
      else find_or_build_connection_pool(:default)
      end
    end

    # Initialize Rails cache if using Redis Cache Store
    def self.initialize_rails_cache!
      cache_store_config = Rails.application.config.cache_store

      if (cache_store_config.is_a?(Array) && cache_store_config[0] == :redis_cache_store) ||
         cache_store_config == :redis_cache_store

        Rails.application.config.cache_store = [
          :redis_cache_store,
          {
            url: url_for(:cache),
            pool: connection_pool_for(:cache),
            error_handler: lambda { |method:, returning:, exception:|
              Rails.logger.error("Redis Cache Error: #{exception.message}")
              Raven.capture_exception(exception) if defined?(Raven)
            }
          }
        ]
      end
    end

    # For backward compatibility
    def self.redis_pool
      if defined?(REDIS_POOL)
        REDIS_POOL
      else
        connection_pool_for(:default)
      end
    end

    # Write a value to the cache
    # @param key [String] The cache key
    # @param value [Object] The value to cache (will be JSON serialized)
    # @param ttl [Integer] Time to live in seconds
    # @return [Boolean] true if successful
    def write(key, value, ttl: DEFAULT_TTL)
      self.class.with_redis(:cache) do |redis|
        redis.setex(normalized_key(key), ttl, ActiveSupport::JSON.encode(value))
      end
      true
    rescue Redis::BaseError => e
      Rails.logger.error("Redis cache write error: #{e.message}")
      false
    end

    # Read a value from the cache
    # @param key [String] The cache key
    # @return [Object, nil] The cached value or nil if not found/expired
    def read(key)
      data = self.class.with_redis(:cache) do |redis|
        redis.get(normalized_key(key))
      end

      return nil if data.nil?

      ActiveSupport::JSON.decode(data)
    rescue Redis::BaseError => e
      Rails.logger.error("Redis cache read error: #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.error("Cache deserialization error: #{e.message}")
      nil
    end

    # Check if a key exists in the cache
    # @param key [String] The cache key
    # @return [Boolean] true if the key exists
    def exist?(key)
      self.class.with_redis(:cache) do |redis|
        redis.exists?(normalized_key(key))
      end
    rescue Redis::BaseError => e
      Rails.logger.error("Redis cache exist? error: #{e.message}")
      false
    end

    # Delete a key from the cache
    # @param key [String] The cache key
    # @return [Boolean] true if successful
    def delete(key)
      self.class.with_redis(:cache) do |redis|
        redis.del(normalized_key(key))
      end
      true
    rescue Redis::BaseError => e
      Rails.logger.error("Redis cache delete error: #{e.message}")
      false
    end

    # Clear all keys matching a pattern
    # @param pattern [String] Pattern to match (e.g., "user:*")
    # @return [Boolean] true if successful
    def clear(pattern = "*")
      self.class.with_redis(:cache) do |redis|
        keys = redis.keys(normalized_key(pattern))
        redis.del(*keys) unless keys.empty?
      end
      true
    rescue Redis::BaseError => e
      Rails.logger.error("Redis cache clear error: #{e.message}")
      false
    end

    def cache_metric(metric)
      self.class.with_redis do |redis|
        # Store the latest value for this metric name
        redis.set(
          "metric:latest:#{metric.name}",
          metric.value
        )

        # Store with dimensions as a hash if dimensions exist
        if metric.dimensions.any?
          # Create a key that includes the dimensions
          dimension_string = metric.dimensions.sort.map { |k, v| "#{k}=#{v}" }.join(",")
          redis.set(
            "metric:latest:#{metric.name}:#{dimension_string}",
            metric.value
          )
        end

        # Add to a time-series sorted set with timestamp as score
        # This allows for sliding window queries and expiration
        timestamp = metric.timestamp.to_i
        redis.zadd(
          "metric:timeseries:#{metric.name}",
          timestamp,
          "#{timestamp}:#{metric.value}"
        )

        # Keep only the last 1000 values (or adjust as needed)
        redis.zremrangebyrank(
          "metric:timeseries:#{metric.name}",
          0,
          -1001
        )

        # Set default expiration for all metrics (30 days)
        [
          "metric:latest:#{metric.name}",
          "metric:timeseries:#{metric.name}"
        ].each do |key|
          redis.expire(key, 30 * 24 * 60 * 60) # 30 days in seconds
        end
      end

      metric
    end

    def get_cached_metric(name, dimensions = {})
      self.class.with_redis do |redis|
        # If dimensions are provided, try to fetch the specific metric
        if dimensions.any?
          dimension_string = dimensions.sort.map { |k, v| "#{k}=#{v}" }.join(",")
          dimension_key = "metric:latest:#{name}:#{dimension_string}"

          # Only return the value if this specific dimension combination exists
          if redis.exists?(dimension_key)
            value = redis.get(dimension_key)
            return value ? value.to_f : nil
          end

          # If the specific dimension doesn't exist, return nil instead of falling back
          return nil
        end

        # Fallback to the general metric name
        value = redis.get("metric:latest:#{name}")
        value ? value.to_f : nil
      end
    end

    def get_metric_history(name, limit = 100)
      self.class.with_redis do |redis|
        # Fetch the most recent metrics from the time series
        redis.zrevrange(
          "metric:timeseries:#{name}",
          0,
          limit - 1
        ).map do |entry|
          timestamp, value = entry.split(":")
          {
            timestamp: Time.at(timestamp.to_i),
            value: value.to_f
          }
        end
      end
    end

    def clear_metric_cache(name = nil)
      self.class.with_redis do |redis|
        if name
          # Clear specific metric cache
          pattern = "metric:*:#{name}*"
          redis.scan_each(match: pattern) do |key|
            redis.del(key)
          end
        else
          # Clear all metrics cache
          pattern = "metric:*"
          redis.scan_each(match: pattern) do |key|
            redis.del(key)
          end
        end
      end
      true
    end

    # Needed for the QueuePort adapter to access Redis
    delegate :redis, to: :class

    private

    # Normalize keys to include a namespace
    def normalized_key(key)
      "cache:#{Rails.env}:#{key}"
    end
  end
end
