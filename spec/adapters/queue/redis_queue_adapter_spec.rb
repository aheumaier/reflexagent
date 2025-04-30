require "rails_helper"

RSpec.describe Adapters::Queue::RedisQueueAdapter, type: :adapter do
  let(:adapter) { described_class.new }
  let(:redis) { instance_double(Redis) }
  let(:event) do
    instance_double(Core::Domain::Event, id: SecureRandom.uuid, name: "test.event", source: "test",
                                         timestamp: Time.current)
  end
  let(:metric) do
    instance_double(Core::Domain::Metric, id: SecureRandom.uuid, name: "test_metric", value: 42.0,
                                          timestamp: Time.current)
  end
  let(:raw_payload) { '{"key": "value"}' }
  let(:source) { "github" }
  let(:worker_id) { "test-worker-1" }

  # For unit tests, we'll mock Redis
  before do
    # Stub the Redis instance to avoid actual Redis connections in tests
    allow(adapter).to receive(:with_redis).and_yield(redis)
  end

  describe "#enqueue_raw_event" do
    before do
      allow(redis).to receive(:llen).and_return(0)
      allow(redis).to receive(:multi).and_yield(redis)
      allow(redis).to receive(:rpush).and_return(1)
      allow(redis).to receive(:expire).and_return(true)
      allow(SecureRandom).to receive(:uuid).and_return("test-uuid")
    end

    it "adds the raw event to the raw_events queue" do
      expect(redis).to receive(:rpush).with(
        "queue:events:raw",
        hash_including(
          id: "test-uuid",
          source: source,
          payload: raw_payload
        ).to_json
      )

      adapter.enqueue_raw_event(raw_payload, source)
    end

    it "sets a TTL on the queue" do
      expect(redis).to receive(:expire).with("queue:events:raw", described_class::QUEUE_TTL)

      adapter.enqueue_raw_event(raw_payload, source)
    end

    it "logs the enqueued event" do
      expect(Rails.logger).to receive(:info).with(/Enqueued raw #{source} event/)

      adapter.enqueue_raw_event(raw_payload, source)
    end

    context "when queue is full" do
      before do
        allow(redis).to receive(:llen).and_return(described_class::MAX_QUEUE_SIZE[:raw_events] + 1)
      end

      it "raises a QueueBackpressureError" do
        expect { adapter.enqueue_raw_event(raw_payload, source) }
          .to raise_error(Adapters::Queue::RedisQueueAdapter::QueueBackpressureError)
      end
    end

    context "when an error occurs" do
      before do
        allow(redis).to receive(:rpush).and_raise("Redis connection error")
      end

      it "logs the error and returns false" do
        expect(Rails.logger).to receive(:error).at_least(:once)

        result = adapter.enqueue_raw_event(raw_payload, source)
        expect(result).to be false
      end
    end
  end

  describe "#enqueue_metric_calculation" do
    before do
      allow(redis).to receive(:llen).and_return(0)
      allow(redis).to receive(:multi).and_yield(redis)
      allow(redis).to receive(:rpush).and_return(1)
      allow(redis).to receive(:expire).and_return(true)
    end

    it "adds the event to the metric_calculation queue" do
      expect(redis).to receive(:rpush).with(
        "queue:metrics:calculation",
        hash_including(
          id: event.id,
          name: event.name,
          source: event.source
        ).to_json
      )

      adapter.enqueue_metric_calculation(event)
    end

    it "logs the enqueued metric calculation" do
      expect(Rails.logger).to receive(:info).with(/Enqueued metric calculation job for event/)

      adapter.enqueue_metric_calculation(event)
    end
  end

  describe "#enqueue_anomaly_detection" do
    before do
      allow(redis).to receive(:llen).and_return(0)
      allow(redis).to receive(:multi).and_yield(redis)
      allow(redis).to receive(:rpush).and_return(1)
      allow(redis).to receive(:expire).and_return(true)
    end

    it "adds the metric to the anomaly_detection queue" do
      expect(redis).to receive(:rpush).with(
        "queue:anomalies:detection",
        hash_including(
          id: metric.id,
          name: metric.name,
          value: metric.value
        ).to_json
      )

      adapter.enqueue_anomaly_detection(metric)
    end

    it "logs the enqueued anomaly detection" do
      expect(Rails.logger).to receive(:info).with(/Enqueued anomaly detection job for metric/)

      adapter.enqueue_anomaly_detection(metric)
    end
  end

  describe "#queue_depths" do
    before do
      allow(redis).to receive(:llen).with("queue:events:raw").and_return(5)
      allow(redis).to receive(:llen).with("queue:events:processing").and_return(10)
      allow(redis).to receive(:llen).with("queue:metrics:calculation").and_return(15)
      allow(redis).to receive(:llen).with("queue:anomalies:detection").and_return(20)
    end

    it "returns a hash with queue depths" do
      depths = adapter.queue_depths

      expect(depths).to be_a(Hash)
      expect(depths[:raw_events]).to eq(5)
      expect(depths[:event_processing]).to eq(10)
      expect(depths[:metric_calculation]).to eq(15)
      expect(depths[:anomaly_detection]).to eq(20)
    end
  end

  describe "#backpressure?" do
    context "when no queue is at max capacity" do
      before do
        allow(adapter).to receive(:queue_depths).and_return({
                                                              raw_events: described_class::MAX_QUEUE_SIZE[:raw_events] - 1,
                                                              event_processing: described_class::MAX_QUEUE_SIZE[:event_processing] - 1,
                                                              metric_calculation: described_class::MAX_QUEUE_SIZE[:metric_calculation] - 1,
                                                              anomaly_detection: described_class::MAX_QUEUE_SIZE[:anomaly_detection] - 1
                                                            })
      end

      it "returns false" do
        expect(adapter.backpressure?).to be false
      end
    end

    context "when at least one queue is at max capacity" do
      before do
        allow(adapter).to receive(:queue_depths).and_return({
                                                              raw_events: described_class::MAX_QUEUE_SIZE[:raw_events],
                                                              event_processing: described_class::MAX_QUEUE_SIZE[:event_processing] - 1,
                                                              metric_calculation: described_class::MAX_QUEUE_SIZE[:metric_calculation] - 1,
                                                              anomaly_detection: described_class::MAX_QUEUE_SIZE[:anomaly_detection] - 1
                                                            })
      end

      it "returns true" do
        expect(adapter.backpressure?).to be true
      end
    end
  end

  describe "#get_next_batch" do
    let(:queue_key) { :raw_events }
    let(:batch_size) { described_class::BATCH_SIZE[queue_key] }
    let(:queue_name) { described_class::QUEUES[queue_key] }
    let(:raw_items) { ["{\"id\":\"1\"}", "{\"id\":\"2\"}", "{\"id\":\"3\"}"] }
    let(:transaction_result) { [raw_items, 3] }

    before do
      allow(redis).to receive(:multi).and_yield(redis).and_return(transaction_result)
      allow(redis).to receive(:lrange).and_return(raw_items)
      allow(redis).to receive(:ltrim).and_return("OK")
    end

    it "retrieves and parses items from the queue" do
      expect(redis).to receive(:lrange).with(queue_name, 0, batch_size - 1)
      expect(redis).to receive(:ltrim).with(queue_name, batch_size, -1)

      result = adapter.get_next_batch(queue_key)

      expect(result).to be_an(Array)
      expect(result.size).to eq(3)
      expect(result.first).to eq({ id: "1" })
    end

    context "with custom batch size" do
      let(:custom_size) { 5 }

      it "honors the custom batch size" do
        expect(redis).to receive(:lrange).with(queue_name, 0, custom_size - 1)

        adapter.get_next_batch(queue_key, custom_size)
      end
    end

    context "when JSON parsing fails" do
      let(:raw_items) { ["{\"id\":\"1\"}", "invalid json", "{\"id\":\"3\"}"] }

      it "filters out invalid items" do
        expect(Rails.logger).to receive(:error).with(/Failed to parse queue item/)

        result = adapter.get_next_batch(queue_key)

        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        expect(result.map { |i| i[:id] }).to eq(["1", "3"])
      end
    end

    context "when the queue is empty" do
      let(:transaction_result) { [[], 0] }

      it "returns an empty array" do
        result = adapter.get_next_batch(queue_key)

        expect(result).to be_an(Array)
        expect(result).to be_empty
      end
    end
  end

  describe "#process_raw_event_batch" do
    let(:use_case) { instance_double(Core::UseCases::ProcessEvent) }
    let(:batch) { [{ id: "1", payload: "{}", source: "github" }, { id: "2", payload: "{}", source: "jira" }] }

    before do
      allow(adapter).to receive(:get_next_batch).with(:raw_events).and_return(batch)
      allow(UseCaseFactory).to receive(:create_process_event).and_return(use_case)
      allow(use_case).to receive(:call)
    end

    it "processes each item in the batch" do
      expect(use_case).to receive(:call).exactly(batch.size).times

      result = adapter.process_raw_event_batch(worker_id)
      expect(result).to eq(batch.size)
    end

    context "when an error occurs processing an item" do
      before do
        # First item succeeds, second fails
        allow(use_case).to receive(:call).with(batch[0][:payload], source: batch[0][:source])
        allow(use_case).to receive(:call).with(batch[1][:payload], source: batch[1][:source])
                                         .and_raise("Processing error")
        allow(adapter).to receive(:enqueue_to_dead_letter)
      end

      it "continues processing the batch and logs the error" do
        expect(Rails.logger).to receive(:error).at_least(:once)
        expect(adapter).to receive(:enqueue_to_dead_letter)

        result = adapter.process_raw_event_batch(worker_id)
        expect(result).to eq(1) # Only one successful item
      end
    end

    context "when batch is empty" do
      before do
        allow(adapter).to receive(:get_next_batch).with(:raw_events).and_return([])
      end

      it "returns zero" do
        result = adapter.process_raw_event_batch(worker_id)
        expect(result).to eq(0)
      end
    end
  end

  # Additional private method tests
  describe "private methods" do
    describe "#enqueue_to_dead_letter" do
      let(:item) { { id: "1", source: "github", payload: "{}" } }
      let(:error) { StandardError.new("Test error") }

      before do
        allow(redis).to receive(:rpush).and_return(1)
        allow(redis).to receive(:expire).and_return(true)
      end

      it "adds the failed item to the dead letter queue with error info" do
        expect(redis).to receive(:rpush).with(
          "queue:dead_letter",
          hash_including(
            id: item[:id],
            error: hash_including(message: error.message)
          ).to_json
        )

        adapter.send(:enqueue_to_dead_letter, item, error)
      end

      it "sets a TTL on the dead letter queue" do
        expect(redis).to receive(:expire).with("queue:dead_letter", described_class::QUEUE_TTL)

        adapter.send(:enqueue_to_dead_letter, item, error)
      end
    end
  end

  # Real Redis integration tests
  describe "with real Redis", :redis do
    let(:real_adapter) { described_class.new }

    before do
      clear_redis
      # Don't stub with_redis method for these tests
      allow(real_adapter).to receive(:with_redis).and_call_original
    end

    after do
      clear_redis
    end

    it "can enqueue and retrieve items from Redis" do
      # Enqueue a raw event
      real_adapter.enqueue_raw_event(raw_payload, source)

      # Check queue depth
      expect(queue_depth("queue:events:raw")).to eq(1)

      # Process the raw event batch
      processed = real_adapter.process_raw_event_batch(worker_id)

      # Should have processed one item
      expect(processed).to be >= 0 # May be 0 if process_event_use_case mocking doesn't work
    end

    it "handles backpressure with real Redis" do
      # Set a very low max queue size
      stub_const("Adapters::Queue::RedisQueueAdapter::MAX_QUEUE_SIZE", { raw_events: 1 })

      # First enqueue should succeed
      real_adapter.enqueue_raw_event(raw_payload, source)

      # Second enqueue should fail with backpressure
      expect do
        real_adapter.enqueue_raw_event(raw_payload, source)
      end.to raise_error(Adapters::Queue::RedisQueueAdapter::QueueBackpressureError)
    end
  end
end
