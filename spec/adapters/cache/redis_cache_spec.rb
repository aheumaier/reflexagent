require "rails_helper"
require_relative "../../../app/adapters/cache/redis_cache"
require_relative "../../../app/core/domain/metric"

RSpec.describe Cache::RedisCache do
  let(:cache) { described_class.new }
  let(:redis) { described_class.redis }
  let(:metric) do
    Domain::Metric.new(
      id: "test-metric-1",
      name: "cpu.usage",
      value: 85.5,
      source: "web-01",
      dimensions: { region: "us-west", environment: "production" },
      timestamp: Time.current
    )
  end

  # Helper method to normalize keys just like the implementation
  def normalized_key(key)
    "cache:#{Rails.env}:#{key}"
  end

  before do
    # Clear Redis before each test
    redis.flushdb
  end

  describe "#cache_metric" do
    it "stores the metric in Redis and returns it" do
      # Cache the metric
      result = cache.cache_metric(metric)

      # Verify the returned metric
      expect(result).to eq(metric)

      # Verify the metric was stored in Redis
      expect(redis.get(normalized_key("metric:latest:#{metric.name}"))).to eq(metric.value.to_s)

      # Verify the metric with dimensions was stored
      dimension_string = metric.dimensions.sort.map { |k, v| "#{k}=#{v}" }.join(",")
      expect(redis.get(normalized_key("metric:latest:#{metric.name}:#{dimension_string}"))).to eq(metric.value.to_s)

      # Verify the time series was updated
      expect(redis.zcard(normalized_key("metric:timeseries:#{metric.name}"))).to eq(1)
    end
  end

  describe "#get_cached_metric" do
    before do
      # Cache a metric
      cache.cache_metric(metric)
    end

    it "retrieves the latest value for a metric by name" do
      value = cache.get_cached_metric("cpu.usage")
      expect(value).to eq(85.5)
    end

    it "retrieves a metric with specific dimensions" do
      value = cache.get_cached_metric("cpu.usage", { region: "us-west", environment: "production" })
      expect(value).to eq(85.5)
    end

    it "returns nil for a non-existent metric" do
      value = cache.get_cached_metric("non.existent")
      expect(value).to be_nil
    end

    it "returns nil for a metric with non-existent dimensions" do
      value = cache.get_cached_metric("cpu.usage", { region: "non-existent" })
      expect(value).to be_nil
    end
  end

  describe "#get_metric_history" do
    before do
      # Cache multiple metrics with different timestamps in a consistent order
      # Make sure timestamps are monotonically decreasing
      cache.cache_metric(
        Domain::Metric.new(
          id: "test-metric-2",
          name: "cpu.usage",
          value: 90.0, # Most recent value should be highest for the test
          source: "web-01",
          dimensions: { region: "us-west" },
          timestamp: 1.hour.ago
        )
      )

      cache.cache_metric(
        Domain::Metric.new(
          id: "test-metric-3",
          name: "cpu.usage",
          value: 85.0,
          source: "web-01",
          dimensions: { region: "us-west" },
          timestamp: 2.hours.ago
        )
      )

      cache.cache_metric(
        Domain::Metric.new(
          id: "test-metric-4",
          name: "cpu.usage",
          value: 80.0, # Oldest value should be lowest for the test
          source: "web-01",
          dimensions: { region: "us-west" },
          timestamp: 3.hours.ago
        )
      )
    end

    it "retrieves the time series data for a metric" do
      history = cache.get_metric_history("cpu.usage")

      # Verify the history has the right number of entries
      expect(history.size).to eq(3)

      # Verify the entries are in reverse chronological order (newest first)
      expect(history.first[:value]).to eq(90.0)
      expect(history.last[:value]).to eq(80.0)
      expect(history.first[:value] > history.last[:value]).to be(true)
    end

    it "limits the number of history entries returned" do
      history = cache.get_metric_history("cpu.usage", 2)
      expect(history.size).to eq(2)
      expect(history.first[:value]).to eq(90.0)
      expect(history.last[:value]).to eq(85.0)
    end
  end

  describe "#clear_metric_cache" do
    before do
      # Cache multiple metrics with different names
      cache.cache_metric(
        Domain::Metric.new(
          id: "test-metric-5",
          name: "cpu.usage",
          value: 85.5,
          source: "web-01",
          timestamp: Time.current
        )
      )

      cache.cache_metric(
        Domain::Metric.new(
          id: "test-metric-6",
          name: "memory.usage",
          value: 70.3,
          source: "web-01",
          timestamp: Time.current
        )
      )
    end

    it "clears cache for a specific metric" do
      # Verify both metrics exist
      expect(redis.get(normalized_key("metric:latest:cpu.usage"))).not_to be_nil
      expect(redis.get(normalized_key("metric:latest:memory.usage"))).not_to be_nil

      # Clear one metric
      cache.clear_metric_cache("cpu.usage")

      # Verify only the specified metric was cleared
      expect(redis.get(normalized_key("metric:latest:cpu.usage"))).to be_nil
      expect(redis.get(normalized_key("metric:latest:memory.usage"))).not_to be_nil
    end

    it "clears all metric caches when no name is specified" do
      # Verify both metrics exist
      expect(redis.get(normalized_key("metric:latest:cpu.usage"))).not_to be_nil
      expect(redis.get(normalized_key("metric:latest:memory.usage"))).not_to be_nil

      # Clear all metrics
      cache.clear_metric_cache

      # Verify all metrics were cleared
      expect(redis.get(normalized_key("metric:latest:cpu.usage"))).to be_nil
      expect(redis.get(normalized_key("metric:latest:memory.usage"))).to be_nil
    end
  end
end
