# frozen_string_literal: true

require "rails_helper"

RSpec.describe Adapters::Queue::RedisQueueAdapter, :redis do
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

  # Since we've consolidated functionality into RedisQueueAdapter,
  # these tests are no longer relevant. The functionality is now tested
  # in redis_queue_adapter_spec.rb

  # Mark all tests as pending with a common message
  let(:pending_message) { "Tests moved to redis_queue_adapter_spec.rb after refactoring" }

  describe "#enqueue", skip: "Tests moved to redis_queue_adapter_spec.rb after refactoring" do
    pending "adds an item to the queue"
    pending "serializes items as JSON"
    pending "sets TTL on the queue when specified"
  end

  describe "#dequeue", skip: "Tests moved to redis_queue_adapter_spec.rb after refactoring" do
    pending "removes and returns the first item from the queue"
    pending "returns nil when the queue is empty"
  end

  describe "#peek", skip: "Tests moved to redis_queue_adapter_spec.rb after refactoring" do
    pending "returns the first item without removing it"
    pending "returns nil when the queue is empty"
  end

  describe "#size", skip: "Tests moved to redis_queue_adapter_spec.rb after refactoring" do
    pending "returns the number of items in the queue"
  end

  describe "#move_to_dlq", skip: "Tests moved to redis_queue_adapter_spec.rb after refactoring" do
    pending "moves a failed item to the dead letter queue"
  end

  describe "#flush", skip: "Tests moved to redis_queue_adapter_spec.rb after refactoring" do
    pending "removes all items from the queue and returns the count"
  end

  describe "#batch_process", skip: "Tests moved to redis_queue_adapter_spec.rb after refactoring" do
    pending "processes items in batches"
    pending "returns 0 when no items are available"
    pending "returns items to the queue on processing error"
  end
end
