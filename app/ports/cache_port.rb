module CachePort
  def cache_metric(metric)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def get_cached_metric(name, dimensions = {})
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def get_metric_history(name, limit = 100)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  def clear_metric_cache(name = nil)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end
end
