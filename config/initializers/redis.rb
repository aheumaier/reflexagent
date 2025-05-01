# frozen_string_literal: true

require "redis"
require "connection_pool"

# Make sure to load ports before adapters to avoid uninitialized constant errors
require_relative "../../app/ports/cache_port"

# Require our Redis-related classes
require_relative "../../app/adapters/cache/redis_manager"
require_relative "../../app/adapters/cache/redis_cache"
require_relative "../../app/adapters/queue/redis_queue_adapter"

# Set up global constants for backward compatibility
REDIS_POOL = Adapters::Cache::RedisManager.connection_pool_for(:default)

# Include RedisHelper module for convenience
module RedisHelper
  def self.with_redis(&)
    Adapters::Cache::RedisManager.with_redis(:default, &)
  end
end

# Configure Rails cache store if using Redis
cache_store_config = Rails.application.config.cache_store
if (cache_store_config.is_a?(Array) && cache_store_config[0] == :redis_cache_store) ||
   cache_store_config == :redis_cache_store

  Rails.application.config.cache_store = [
    :redis_cache_store,
    {
      url: Adapters::Cache::RedisManager.url_for(:cache),
      pool: Adapters::Cache::RedisManager.connection_pool_for(:cache),
      error_handler: lambda { |method:, returning:, exception:|
        Rails.logger.error("Redis Cache Error: #{exception.message}")
        Raven.capture_exception(exception) if defined?(Raven) # Log to Sentry if available
      }
    }
  ]
end
