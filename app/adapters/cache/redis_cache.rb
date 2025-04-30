module Adapters
  module Cache
    class RedisCache
      include Ports::CachePort

      # Redis connection singleton
      def self.redis
        @redis ||= Redis.new(
          url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
          reconnect_attempts: 3,
          reconnect_delay: 0.5
        )
      end

      def cache_metric(metric)
        # Store the latest value for this metric name
        redis.set(
          "metric:latest:#{metric.name}",
          metric.value
        )

        # Store with dimensions as a hash if dimensions exist
        if metric.dimensions.any?
          # Create a key that includes the dimensions
          dimension_string = metric.dimensions.sort.map { |k, v| "#{k}=#{v}" }.join(',')
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

        metric
      end

      def get_cached_metric(name, dimensions = {})
        # If dimensions are provided, try to fetch the specific metric
        if dimensions.any?
          dimension_string = dimensions.sort.map { |k, v| "#{k}=#{v}" }.join(',')
          value = redis.get("metric:latest:#{name}:#{dimension_string}")
          return value.to_f if value
        end

        # Fallback to the general metric name
        value = redis.get("metric:latest:#{name}")
        value ? value.to_f : nil
      end

      def get_metric_history(name, limit = 100)
        # Fetch the most recent metrics from the time series
        redis.zrevrange(
          "metric:timeseries:#{name}",
          0,
          limit - 1
        ).map do |entry|
          timestamp, value = entry.split(':')
          {
            timestamp: Time.at(timestamp.to_i),
            value: value.to_f
          }
        end
      end

      def clear_metric_cache(name = nil)
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
        true
      end

      private

      def redis
        self.class.redis
      end
    end
  end
end
