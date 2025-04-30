require "rails_helper"
require_relative "../../app/adapters/cache/redis_cache"
require_relative "../../app/core/domain/metric"

RSpec.describe "Metric Caching", type: :integration do
  let(:cache) { Adapters::Cache::RedisCache.new }
  let(:redis) { Adapters::Cache::RedisCache.redis }

  # Helper method to create a test metric
  def create_test_metric(options = {})
    Core::Domain::Metric.new(
      name: options[:name] || "test.metric",
      value: options[:value] || 85.5,
      source: options[:source] || "test-source",
      dimensions: options[:dimensions] || { region: "test-region", environment: "test" },
      timestamp: options[:timestamp] || Time.current,
      id: options[:id]
    )
  end

  describe "end-to-end Redis caching" do
    before do
      # Clean Redis before each test
      redis.flushdb
    end

    after do
      # Clean up after tests
      redis.flushdb
    end

    it "caches metrics and retrieves them by name" do
      # Create and cache a metric
      metric = create_test_metric(name: "system.cpu.usage", value: 75.0)
      result = cache.cache_metric(metric)

      # Verify the returned metric
      expect(result).to eq(metric)

      # Verify the metric exists in Redis
      expect(redis.exists?("metric:latest:system.cpu.usage")).to be true

      # Verify we can retrieve the cached value
      cached_value = cache.get_cached_metric("system.cpu.usage")
      expect(cached_value).to eq(75.0)
    end

    it "updates cached values when newer metrics arrive" do
      # Cache initial metric
      metric1 = create_test_metric(name: "system.memory.usage", value: 45.5)
      cache.cache_metric(metric1)

      # Verify initial value
      initial_value = cache.get_cached_metric("system.memory.usage")
      expect(initial_value).to eq(45.5)

      # Cache an updated metric
      metric2 = create_test_metric(name: "system.memory.usage", value: 60.2)
      cache.cache_metric(metric2)

      # Verify value was updated
      updated_value = cache.get_cached_metric("system.memory.usage")
      expect(updated_value).to eq(60.2)
    end

    it "supports dimension-specific metrics" do
      # Cache metrics with different dimensions
      cache.cache_metric(create_test_metric(
                           name: "http.response_time",
                           value: 120.0,
                           dimensions: { endpoint: "/api/users", method: "GET" }
                         ))

      cache.cache_metric(create_test_metric(
                           name: "http.response_time",
                           value: 250.0,
                           dimensions: { endpoint: "/api/orders", method: "POST" }
                         ))

      # Retrieve general metric (should return the most recent value)
      general_value = cache.get_cached_metric("http.response_time")
      expect(general_value).to be_a(Float)

      # Retrieve dimension-specific metrics
      users_get = cache.get_cached_metric("http.response_time", {
                                            endpoint: "/api/users",
                                            method: "GET"
                                          })

      orders_post = cache.get_cached_metric("http.response_time", {
                                              endpoint: "/api/orders",
                                              method: "POST"
                                            })

      # Verify dimension-specific values
      expect(users_get).to eq(120.0)
      expect(orders_post).to eq(250.0)
    end

    it "returns nil for non-existent cached metrics" do
      # Try to get a metric that doesn't exist
      value = cache.get_cached_metric("non.existent.metric")

      # Should return nil
      expect(value).to be_nil
    end

    it "returns nil for non-existent dimensions" do
      # Cache a metric with specific dimensions
      cache.cache_metric(create_test_metric(
                           name: "service.latency",
                           dimensions: { service: "auth" }
                         ))

      # Try to get the same metric with different dimensions
      value = cache.get_cached_metric("service.latency", { service: "payments" })

      # Should return nil
      expect(value).to be_nil
    end
  end

  describe "time series caching" do
    before do
      # Clean Redis
      redis.flushdb

      # Create a time series of metrics
      5.times do |i|
        cache.cache_metric(create_test_metric(
                             name: "time_series.metric",
                             value: 100.0 + (i * 10),
                             timestamp: (5 - i).minutes.ago
                           ))
      end
    end

    after do
      redis.flushdb
    end

    it "maintains a time series of metrics" do
      # Verify the time series exists in Redis
      expect(redis.exists?("metric:timeseries:time_series.metric")).to be true

      # Verify the time series has the right number of entries
      count = redis.zcard("metric:timeseries:time_series.metric")
      expect(count).to eq(5)

      # Retrieve the history
      history = cache.get_metric_history("time_series.metric")

      # Verify we got the right number of entries
      expect(history.size).to eq(5)

      # Verify entries are in reverse chronological order (newest first)
      expect(history.first[:value]).to be > history.last[:value]

      # The first value should be the most recent (highest value = 140.0)
      expect(history.first[:value]).to eq(140.0)
    end

    it "limits the number of history entries returned" do
      # Get history with a limit of 3
      limited_history = cache.get_metric_history("time_series.metric", 3)

      # Verify we only got 3 entries
      expect(limited_history.size).to eq(3)

      # The values should be the 3 most recent (140, 130, 120)
      values = limited_history.map { |entry| entry[:value] }
      expect(values).to eq([140.0, 130.0, 120.0])
    end

    it "automatically trims the time series when it gets too large" do
      # Cache enough metrics to trigger trimming
      1001.times do |i|
        cache.cache_metric(create_test_metric(
                             name: "trim_test.metric",
                             value: i.to_f,
                             timestamp: Time.current - i.seconds
                           ))
      end

      # Verify the time series was trimmed to 1000 entries
      count = redis.zcard("metric:timeseries:trim_test.metric")
      expect(count).to eq(1000)

      # The oldest entries should have been removed
      min_score = redis.zrange("metric:timeseries:trim_test.metric", 0, 0, with_scores: true)[0][1]
      expect(min_score).to be > 1001.seconds.ago.to_i
    end
  end

  describe "cache clearing" do
    before do
      # Clean Redis
      redis.flushdb

      # Cache multiple metrics
      cache.cache_metric(create_test_metric(name: "test.metric1", value: 10.0))
      cache.cache_metric(create_test_metric(name: "test.metric2", value: 20.0))
      cache.cache_metric(create_test_metric(name: "other.metric", value: 30.0))
    end

    after do
      redis.flushdb
    end

    it "clears specific metric caches" do
      # Verify all metrics exist
      expect(redis.exists?("metric:latest:test.metric1")).to be true
      expect(redis.exists?("metric:latest:test.metric2")).to be true
      expect(redis.exists?("metric:latest:other.metric")).to be true

      # Clear one specific metric
      cache.clear_metric_cache("test.metric1")

      # Verify only that metric was cleared
      expect(redis.exists?("metric:latest:test.metric1")).to be false
      expect(redis.exists?("metric:latest:test.metric2")).to be true
      expect(redis.exists?("metric:latest:other.metric")).to be true
    end

    it "clears metrics with a pattern" do
      # Clear all 'test' metrics
      cache.clear_metric_cache("test")

      # Verify all 'test' metrics were cleared
      expect(redis.exists?("metric:latest:test.metric1")).to be false
      expect(redis.exists?("metric:latest:test.metric2")).to be false

      # But other metrics remain
      expect(redis.exists?("metric:latest:other.metric")).to be true
    end

    it "clears all metrics when no name is specified" do
      # Clear all metrics
      cache.clear_metric_cache

      # Verify all metrics were cleared
      expect(redis.exists?("metric:latest:test.metric1")).to be false
      expect(redis.exists?("metric:latest:test.metric2")).to be false
      expect(redis.exists?("metric:latest:other.metric")).to be false
    end
  end

  describe "key expiration" do
    it "sets TTL on cached metrics" do
      # Cache a metric
      cache.cache_metric(create_test_metric)

      # Check that TTL is set (should be ~30 days)
      ttl = redis.ttl("metric:latest:test.metric")
      expect(ttl).to be > 29 * 24 * 60 * 60 # Almost 30 days in seconds
      expect(ttl).to be <= 30 * 24 * 60 * 60 # 30 days in seconds
    end
  end
end
