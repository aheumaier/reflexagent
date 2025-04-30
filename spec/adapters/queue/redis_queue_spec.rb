# frozen_string_literal: true

require "rails_helper"

RSpec.describe Adapters::Queue::RedisQueue, :redis do
  include RedisHelpers

  let(:queue) { described_class.new }
  let(:test_queue) { "test_queue_#{SecureRandom.hex(4)}" }

  before do
    # Clear any existing test queues
    clear_redis("queue:test:*")
  end

  after do
    # Clean up after tests
    clear_redis("queue:test:*")
  end

  describe "#enqueue" do
    it "adds an item to the queue" do
      expect do
        queue.enqueue({ id: 1, name: "Test Item" }, queue_name: test_queue)
      end.to change { queue_depth(test_queue) }.by(1)
    end

    it "serializes items as JSON" do
      queue.enqueue({ id: 1, name: "Test Item" }, queue_name: test_queue)

      Adapters::Cache::RedisManager.with_redis do |redis|
        raw_item = redis.lindex("queue:test:#{test_queue}", 0)
        parsed = JSON.parse(raw_item)

        expect(parsed).to include("id" => 1, "name" => "Test Item")
      end
    end

    it "sets TTL on the queue when specified" do
      queue.enqueue({ id: 1 }, queue_name: test_queue, ttl: 100)

      Adapters::Cache::RedisManager.with_redis do |redis|
        ttl = redis.ttl("queue:test:#{test_queue}")
        expect(ttl).to be_between(1, 100)
      end
    end
  end

  describe "#dequeue" do
    before do
      queue.enqueue({ id: 1, name: "First" }, queue_name: test_queue)
      queue.enqueue({ id: 2, name: "Second" }, queue_name: test_queue)
    end

    it "removes and returns the first item from the queue" do
      item = queue.dequeue(queue_name: test_queue)

      expect(item).to include(id: 1, name: "First")
      expect(queue_depth(test_queue)).to eq(1)
    end

    it "returns nil when the queue is empty" do
      empty_queue = "empty_queue"

      expect(queue.dequeue(queue_name: empty_queue)).to be_nil
    end
  end

  describe "#peek" do
    before do
      queue.enqueue({ id: 1, name: "First" }, queue_name: test_queue)
      queue.enqueue({ id: 2, name: "Second" }, queue_name: test_queue)
    end

    it "returns the first item without removing it" do
      item = queue.peek(queue_name: test_queue)

      expect(item).to include(id: 1, name: "First")
      expect(queue_depth(test_queue)).to eq(2)
    end

    it "returns nil when the queue is empty" do
      empty_queue = "empty_queue"

      expect(queue.peek(queue_name: empty_queue)).to be_nil
    end
  end

  describe "#size" do
    it "returns the number of items in the queue" do
      expect(queue.size(queue_name: test_queue)).to eq(0)

      queue.enqueue({ id: 1 }, queue_name: test_queue)
      queue.enqueue({ id: 2 }, queue_name: test_queue)

      expect(queue.size(queue_name: test_queue)).to eq(2)
    end
  end

  describe "#move_to_dlq" do
    it "moves a failed item to the dead letter queue" do
      failed_item = { id: 1, name: "Failed Item" }
      error = StandardError.new("Test Error")

      queue.move_to_dlq(failed_item, queue_name: test_queue, error: error)

      dlq_item = queue.dequeue(queue_name: "#{test_queue}#{described_class::DLQ_SUFFIX}")

      expect(dlq_item).to include(
        original_item: failed_item,
        error: "Test Error"
      )
      expect(dlq_item[:backtrace]).to be_an(Array)
      expect(dlq_item[:failed_at]).not_to be_nil
    end
  end

  describe "#flush" do
    it "removes all items from the queue and returns the count" do
      queue.enqueue({ id: 1 }, queue_name: test_queue)
      queue.enqueue({ id: 2 }, queue_name: test_queue)

      expect(queue.flush(queue_name: test_queue)).to eq(2)
      expect(queue.size(queue_name: test_queue)).to eq(0)
    end
  end

  describe "#batch_process" do
    before do
      10.times do |i|
        queue.enqueue({ id: i }, queue_name: test_queue)
      end
    end

    it "processes items in batches" do
      processed_items = []

      result = queue.batch_process(queue_name: test_queue, batch_size: 5) do |items|
        processed_items = items
      end

      expect(result).to eq(5)
      expect(processed_items.size).to eq(5)
      expect(processed_items.first).to include(id: 0)
      expect(queue.size(queue_name: test_queue)).to eq(5)
    end

    it "returns 0 when no items are available" do
      empty_queue = "empty_queue"

      result = queue.batch_process(queue_name: empty_queue) do |items|
        # This should not be called
        raise "Should not be called"
      end

      expect(result).to eq(0)
    end

    it "returns items to the queue on processing error" do
      expect do
        queue.batch_process(queue_name: test_queue, batch_size: 5) do |_items|
          raise "Processing error"
        end
      end.to raise_error("Processing error")

      # Items should be returned to the queue
      expect(queue.size(queue_name: test_queue)).to eq(10)
    end
  end
end
