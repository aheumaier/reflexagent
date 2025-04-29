module Adapters
  module Cache
    class RedisCache
      include Ports::CachePort

      def cache_metric(metric)
        # Implementation of CachePort#cache_metric
        # Will store in Redis in a real implementation
        metric
      end

      def get_cached_metric(name, dimensions = {})
        # Implementation of CachePort#get_cached_metric
        # Will retrieve from Redis in a real implementation
        nil
      end

      def clear_metric_cache(name = nil)
        # Implementation of CachePort#clear_metric_cache
        # Will clear Redis keys in a real implementation
        true
      end
    end
  end
end
