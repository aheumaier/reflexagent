# frozen_string_literal: true

module Adapters
  module Cache
    class RedisCache
      include Ports::CachePort

      # Redis connection management
      def self.redis
        # If using the connection pool (preferred for thread safety)
        if defined?(REDIS_POOL)
          # Just return the pool - callers should use with_redis for thread safety
          REDIS_POOL
        else
          # Fallback for older code or tests
          @redis ||= Redis.new(
            url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
            reconnect_attempts: 3
          )
        end
      end

      # Helper method to execute a block with a Redis connection
      def self.with_redis(&)
        if defined?(REDIS_POOL)
          REDIS_POOL.with(&)
        else
          yield redis
        end
      end

      # Default expiration time of 1 hour if not specified
      DEFAULT_TTL = 3600

      # Write a value to the cache
      # @param key [String] The cache key
      # @param value [Object] The value to cache (will be JSON serialized)
      # @param ttl [Integer] Time to live in seconds
      # @return [Boolean] true if successful
      def write(key, value, ttl: DEFAULT_TTL)
        Adapters::Cache::RedisManager.with_redis(:cache) do |redis|
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
        data = Adapters::Cache::RedisManager.with_redis(:cache) do |redis|
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
        Adapters::Cache::RedisManager.with_redis(:cache) do |redis|
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
        Adapters::Cache::RedisManager.with_redis(:cache) do |redis|
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
        Adapters::Cache::RedisManager.with_redis(:cache) do |redis|
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
end
