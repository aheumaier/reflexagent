# frozen_string_literal: true

# Helper methods for testing Redis-dependent code
module RedisHelpers
  # Get a Redis client for testing
  # @return [Redis, nil] A Redis client or nil if Redis is not available
  delegate :redis_client, to: :class

  # Check if Redis is available for testing
  # @return [Boolean] true if Redis is available, false otherwise
  delegate :redis_available?, to: :class

  # Clear all test-related Redis keys
  # @param pattern [String] Pattern of keys to clear
  # @return [Boolean] true if successful
  def clear_redis(pattern = "queue:*")
    return true unless self.class.redis_available?

    Cache::RedisManager.with_redis do |redis|
      redis.keys(pattern).each do |key|
        redis.del(key)
      end
    end
    true
  end

  # Get the length of a Redis list
  # @param queue_name [String] Name of the queue
  # @return [Integer] Queue length
  def queue_depth(queue_name)
    return 0 unless self.class.redis_available?

    Cache::RedisManager.with_redis do |redis|
      redis.llen("queue:test:#{queue_name}")
    end
  end

  # Class methods
  class << self
    # Get a Redis client for testing
    # @return [Redis, nil] A Redis client or nil if Redis is not available
    def redis_client
      @redis_client ||= begin
        Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
      rescue Redis::CannotConnectError
        nil
      end
    end

    # Check if Redis is available for testing
    # @return [Boolean] true if Redis is available, false otherwise
    def redis_available?
      return @redis_available if defined?(@redis_available)

      begin
        # Try to connect and ping Redis
        Cache::RedisManager.with_redis do |redis|
          redis.ping
        end
        @redis_available = true
      rescue Redis::CannotConnectError, Redis::ConnectionError => e
        Rails.logger.warn("Redis not available for tests: #{e.message}")
        @redis_available = false
      end

      @redis_available
    end

    # Skip a test if Redis is not available
    def skip_if_redis_unavailable(example)
      skip "Redis server is not available" unless redis_available?
      example.run
    end
  end

  # RSpec metadata helper to conditionally run Redis tests
  # Usage: it "tests something with Redis", :redis do
  #          # Test code that assumes Redis is available
  #        end
  RSpec.configure do |config|
    config.around(:each, :redis) do |example|
      RedisHelpers.skip_if_redis_unavailable(example)
    end
  end
end
