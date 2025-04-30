# frozen_string_literal: true

module Adapters
  module Cache
    class RedisManager
      class_attribute :connection_pool_cache, default: {}

      def self.default_url
        ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
      end

      def self.url_for_or_default(key)
        ENV[key].presence || default_url
      end

      # Return the URL to a Redis DB for a given purpose
      def self.url_for(purpose = :default)
        case purpose.to_sym
        when :cache then url_for_or_default("REDIS_CACHE_URL")
        when :queue then url_for_or_default("REDIS_QUEUE_URL")
        when :throttling then url_for_or_default("REDIS_THROTTLING_URL")
        when :default then default_url
        end
      end

      def self.connection_pool_size
        ENV.fetch("REDIS_POOL_SIZE", 10).to_i
      end

      def self.connection_pool_timeout
        ENV.fetch("REDIS_POOL_TIMEOUT", 5).to_i
      end

      def self.build_connection_pool(purpose)
        ConnectionPool.new(size: connection_pool_size, timeout: connection_pool_timeout) do
          # Create Redis client with compatible options
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

      def self.find_or_build_connection_pool(purpose)
        connection_pool_cache[purpose] ||= build_connection_pool(purpose)
      end

      # Return a memoized ConnectionPool instance for a given purpose
      def self.connection_pool_for(purpose = :default)
        case purpose.to_sym
        when :cache then find_or_build_connection_pool(:cache)
        when :queue then find_or_build_connection_pool(:queue)
        when :throttling then find_or_build_connection_pool(:throttling)
        when :default then find_or_build_connection_pool(:default)
        end
      end

      # Convenience method for getting a Redis connection from a specific pool
      def self.with_redis(purpose = :default, &)
        connection_pool_for(purpose).with(&)
      end
    end
  end
end
