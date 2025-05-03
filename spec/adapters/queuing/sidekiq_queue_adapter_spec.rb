# frozen_string_literal: true

require "rails_helper"

RSpec.describe Queuing::SidekiqQueueAdapter, type: :adapter do
  subject(:adapter) { described_class.new }

  let(:event) { instance_double(Core::Domain::Event, id: "event-123", type: "test", data: {}, metadata: {}) }
  let(:metric) { instance_double(Core::Domain::Metric, id: "metric-123", name: "test_metric", value: 42) }
  let(:raw_payload) { '{"test":"data"}' }
  let(:source) { "github" }

  before do
    # Stub Sidekiq Stats API for queue depths
    allow(Sidekiq::Stats).to receive(:new).and_return(
      instance_double(Sidekiq::Stats, queues: {
                        "raw_events" => 5,
                        "event_processing" => 3,
                        "metric_calculation" => 2
                      })
    )
  end

  describe "#enqueue_raw_event" do
    it "enqueues a raw event job" do
      expect(RawEventJob).to receive(:perform_async).with(
        hash_including(source: source, payload: raw_payload)
      )

      result = adapter.enqueue_raw_event(raw_payload, source)

      expect(result).to be(true)
    end

    context "when there is backpressure" do
      before do
        allow(adapter).to receive(:backpressure?).and_return(true)
      end

      it "raises a QueueBackpressureError" do
        expect do
          adapter.enqueue_raw_event(raw_payload, source)
        end.to raise_error(Queuing::SidekiqQueueAdapter::QueueBackpressureError)
      end
    end
  end

  describe "#enqueue_metric_calculation" do
    it "enqueues a metric calculation job with the event id" do
      expect(MetricCalculationJob).to receive(:perform_async).with(event.id)

      result = adapter.enqueue_metric_calculation(event)

      expect(result).to be(true)
    end
  end

  describe "#enqueue_anomaly_detection" do
    it "enqueues an anomaly detection job with the metric id" do
      expect(AnomalyDetectionJob).to receive(:perform_async).with(metric.id)

      result = adapter.enqueue_anomaly_detection(metric)

      expect(result).to be(true)
    end
  end

  describe "#queue_depths" do
    it "returns queue depths from Sidekiq stats" do
      depths = adapter.queue_depths

      expect(depths[:raw_events]).to eq(5)
      expect(depths[:event_processing]).to eq(3)
      expect(depths[:metric_calculation]).to eq(2)
      expect(depths[:anomaly_detection]).to eq(0) # Not in the mock data, defaults to 0
    end
  end

  describe "#backpressure?" do
    context "when no queues are full" do
      before do
        allow(adapter).to receive(:queue_depths).and_return({
                                                              raw_events: 100,
                                                              event_processing: 50,
                                                              metric_calculation: 20,
                                                              anomaly_detection: 10
                                                            })
      end

      it "returns false" do
        expect(adapter.backpressure?).to be(false)
      end
    end

    context "when a queue is full" do
      before do
        allow(adapter).to receive(:queue_depths).and_return({
                                                              raw_events: 60_000, # Exceeds MAX_QUEUE_SIZE[:raw_events]
                                                              event_processing: 50,
                                                              metric_calculation: 20,
                                                              anomaly_detection: 10
                                                            })
      end

      it "returns true" do
        expect(adapter.backpressure?).to be(true)
      end
    end
  end
end
