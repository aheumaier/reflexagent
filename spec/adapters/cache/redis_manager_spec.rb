# frozen_string_literal: true

require "rails_helper"

RSpec.describe Adapters::Cache::RedisManager do
  describe ".url_for" do
    it "returns the default URL for :default purpose" do
      allow(ENV).to receive(:fetch).with("REDIS_URL", "redis://localhost:6379/0").and_return("redis://test:6379/0")

      expect(described_class.url_for(:default)).to eq("redis://test:6379/0")
    end

    it "returns a purpose-specific URL if available" do
      allow(ENV).to receive(:[]).with("REDIS_CACHE_URL").and_return("redis://cache:6379/1")
      allow(described_class).to receive(:default_url).and_return("redis://default:6379/0")

      expect(described_class.url_for(:cache)).to eq("redis://cache:6379/1")
    end

    it "falls back to default URL if purpose-specific URL is not set" do
      allow(ENV).to receive(:[]).with("REDIS_CACHE_URL").and_return(nil)
      allow(described_class).to receive(:default_url).and_return("redis://default:6379/0")

      expect(described_class.url_for(:cache)).to eq("redis://default:6379/0")
    end
  end

  describe ".connection_pool_for", :redis do
    it "returns a ConnectionPool instance" do
      pool = described_class.connection_pool_for(:default)

      expect(pool).to be_a(ConnectionPool)
    end

    it "memoizes connection pools" do
      pool1 = described_class.connection_pool_for(:default)
      pool2 = described_class.connection_pool_for(:default)

      expect(pool1).to be(pool2)
    end

    it "creates different pools for different purposes" do
      default_pool = described_class.connection_pool_for(:default)
      cache_pool = described_class.connection_pool_for(:cache)

      expect(default_pool).not_to be(cache_pool)
    end
  end

  describe ".with_redis", :redis do
    it "yields a Redis instance" do
      yielded_client = nil

      described_class.with_redis do |redis|
        yielded_client = redis
      end

      expect(yielded_client).to be_a(Redis)
    end

    it "returns the result of the block" do
      result = described_class.with_redis { |redis| "test result" }

      expect(result).to eq("test result")
    end
  end
end
