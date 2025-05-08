# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cache::EventLRUCache, type: :unit do
  include RedisHelpers

  let(:redis_client) { instance_double(Redis) }
  let(:logger) { instance_double(Logger, debug: nil, error: nil) }
  let(:redis_cache) { instance_double(Cache::RedisCache) }
  let(:cache) { described_class.new(redis_cache: redis_cache, max_size: 10, logger: logger) }

  let(:event) do
    Domain::Event.new(
      id: "123",
      name: "test.event",
      source: "test-source",
      data: { "value" => 123 },
      timestamp: Time.current
    )
  end

  before do
    allow(Cache::RedisCache).to receive(:with_redis).and_yield(redis_client)
  end

  describe "#get" do
    it "returns nil when event is not in cache" do
      # Mock pipeline results: [get_result, zadd_result]
      pipeline_results = [nil, 1]
      allow(redis_client).to receive(:pipelined).and_yield(redis_client).and_return(pipeline_results)
      allow(redis_client).to receive(:get)
      allow(redis_client).to receive(:zadd)

      result = cache.get("123")

      expect(result).to be_nil
    end

    it "returns the event when found in cache" do
      serialized_event = {
        "id" => "123",
        "name" => "test.event",
        "source" => "test-source",
        "data" => { "value" => 123 },
        "timestamp" => Time.current.iso8601
      }.to_json

      # Mock pipeline results: [get_result, zadd_result]
      pipeline_results = [serialized_event, 1]
      allow(redis_client).to receive(:pipelined).and_yield(redis_client).and_return(pipeline_results)
      allow(redis_client).to receive(:get)
      allow(redis_client).to receive(:zadd)

      result = cache.get("123")

      expect(result).to be_a(Domain::Event)
      expect(result.id).to eq("123")
      expect(result.name).to eq("test.event")
    end

    it "handles errors gracefully" do
      allow(redis_client).to receive(:pipelined).and_raise(StandardError.new("Test error"))

      result = cache.get("123")

      expect(result).to be_nil
    end
  end

  describe "#put" do
    it "stores the event in cache" do
      # Allow the evict_if_needed method to run
      allow(redis_client).to receive(:zcard).and_return(0)

      # Mock the Redis client for pipelined operation
      allow(redis_client).to receive(:pipelined).and_yield(redis_client)
      allow(redis_client).to receive(:setex)
      allow(redis_client).to receive(:zadd)

      result = cache.put(event)

      expect(result).to eq(event)
      expect(redis_client).to have_received(:setex).with(
        "event_cache:123",
        Cache::EventLRUCache::DEFAULT_TTL,
        kind_of(String)
      )
      expect(redis_client).to have_received(:zadd).with(
        "event_cache:index",
        kind_of(Integer),
        "123"
      )
    end

    it "handles errors gracefully" do
      allow(redis_client).to receive(:zcard).and_return(0) # For evict_if_needed
      allow(redis_client).to receive(:pipelined).and_raise(StandardError.new("Test error"))

      result = cache.put(event)

      expect(result).to eq(event)
    end
  end

  describe "#clear" do
    it "clears the cache" do
      # Setup for empty cache case
      allow(redis_client).to receive(:zrange).with("event_cache:index", 0, -1).and_return([])
      allow(redis_client).to receive(:del).with("event_cache:index")

      result = cache.clear

      expect(result).to be true
      expect(redis_client).to have_received(:del).with("event_cache:index")
    end

    it "clears the cache with items" do
      # Setup for non-empty cache case
      event_ids = ["123", "456"]
      allow(redis_client).to receive(:zrange).with("event_cache:index", 0, -1).and_return(event_ids)
      allow(redis_client).to receive(:pipelined).and_yield(redis_client)
      allow(redis_client).to receive(:del).with("event_cache:123")
      allow(redis_client).to receive(:del).with("event_cache:456")
      allow(redis_client).to receive(:del).with("event_cache:index")

      result = cache.clear

      expect(result).to be true
      expect(redis_client).to have_received(:del).with("event_cache:123")
      expect(redis_client).to have_received(:del).with("event_cache:456")
      expect(redis_client).to have_received(:del).with("event_cache:index")
    end
  end

  describe "#size" do
    it "returns the cache size" do
      allow(redis_client).to receive(:zcard).with("event_cache:index").and_return(3)

      result = cache.size

      expect(result).to eq(3)
    end

    it "returns 0 when index doesn't exist" do
      allow(redis_client).to receive(:zcard).with("event_cache:index").and_return(0)

      result = cache.size

      expect(result).to eq(0)
    end
  end
end
