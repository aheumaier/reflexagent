require "rails_helper"
require_relative "../../../app/adapters/queue/redis_queue_adapter"
require_relative "../../../app/core/domain/event"
require_relative "../../../app/core/domain/metric"

RSpec.describe Adapters::Queue::RedisQueueAdapter do
  # Since we're using the same class that's already well-tested in redis_queue_adapter_spec.rb,
  # this is just a minimal test to ensure the specific methods we moved from ProcessEventWorker
  # are working correctly

  let(:adapter) { described_class.new }

  # Mock the redis dependency to avoid actual Redis operations
  before do
    allow(adapter).to receive(:with_redis).and_yield(double("redis"))
    allow(adapter).to receive(:enqueue_item).and_return(true)
  end

  let(:event) do
    Domain::EventFactory.create(
      name: "server.cpu.usage",
      data: { value: 85.5, host: "web-01" },
      source: "monitoring-agent"
    )
  end
  let(:metric) do
    Domain::Metric.new(
      name: "cpu.usage",
      value: 85.5,
      source: "web-01",
      dimensions: { region: "us-west", environment: "production" }
    )
  end

  describe "#enqueue_metric_calculation" do
    it "enqueues a job to calculate metrics from the event" do
      expect(adapter).to receive(:enqueue_item).with(:metric_calculation, hash_including(id: event.id))
      result = adapter.enqueue_metric_calculation(event)
      expect(result).to be true
    end
  end

  describe "#enqueue_anomaly_detection" do
    it "enqueues a job to detect anomalies based on the metric" do
      expect(adapter).to receive(:enqueue_item).with(:anomaly_detection, hash_including(id: metric.id))
      result = adapter.enqueue_anomaly_detection(metric)
      expect(result).to be true
    end
  end

  describe "#enqueue_event_processing" do
    it "enqueues a job to process an event" do
      expect(adapter).to receive(:enqueue_item).with(:event_processing, hash_including(id: event.id))
      result = adapter.enqueue_event_processing(event)
      expect(result).to be true
    end
  end
end
