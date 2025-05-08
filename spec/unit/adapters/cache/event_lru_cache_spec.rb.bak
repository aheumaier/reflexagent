# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cache::EventLRUCache, type: :unit do
  include RedisHelpers

  let(:redis_cache) { instance_double(Cache::RedisCache) }
  let(:logger) { instance_double(Logger, debug: nil, error: nil) }
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

  describe "#get" do
    it "returns nil when event is not in cache" do
      allow(redis_cache).to receive(:read).with("event_cache:123").and_return(nil)

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
      }

      allow(redis_cache).to receive(:read).with("event_cache:123").and_return(serialized_event)
      allow(cache).to receive(:update_access_time)

      result = cache.get("123")

      expect(result).to be_a(Domain::Event)
      expect(result.id).to eq("123")
      expect(result.name).to eq("test.event")
    end

    it "handles errors gracefully" do
      allow(redis_cache).to receive(:read).and_raise(StandardError.new("Test error"))

      result = cache.get("123")

      expect(result).to be_nil
    end
  end

  describe "#put" do
    it "stores the event in cache" do
      allow(redis_cache).to receive(:write)
      allow(cache).to receive(:update_access_time)
      allow(cache).to receive(:add_to_index)
      allow(cache).to receive(:evict_if_needed)

      result = cache.put(event)

      expect(result).to eq(event)
      expect(redis_cache).to have_received(:write).with(
        "event_cache:123",
        kind_of(Hash),
        ttl: Cache::EventLRUCache::DEFAULT_TTL
      )
    end

    it "handles errors gracefully" do
      allow(redis_cache).to receive(:write).and_raise(StandardError.new("Test error"))
      # Mock the size method to avoid the call to redis_cache.read
      allow(cache).to receive(:size).and_return(0)
      # Mock other methods that might be called
      allow(cache).to receive(:evict_if_needed)
      allow(cache).to receive(:update_access_time)
      allow(cache).to receive(:add_to_index)

      result = cache.put(event)

      expect(result).to eq(event)
    end
  end

  describe "#clear" do
    it "clears the cache" do
      allow(redis_cache).to receive(:delete)
      allow(redis_cache).to receive(:clear)

      result = cache.clear

      expect(result).to be true
      expect(redis_cache).to have_received(:delete).with("event_cache:index")
      expect(redis_cache).to have_received(:clear).with("event_cache:*")
    end
  end

  describe "#size" do
    it "returns the cache size" do
      allow(redis_cache).to receive(:read).with("event_cache:index").and_return(["1", "2", "3"])

      result = cache.size

      expect(result).to eq(3)
    end

    it "returns 0 when index doesn't exist" do
      allow(redis_cache).to receive(:read).with("event_cache:index").and_return(nil)

      result = cache.size

      expect(result).to eq(0)
    end
  end
end
