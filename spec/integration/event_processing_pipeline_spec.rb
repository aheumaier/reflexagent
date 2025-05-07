# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Event Processing Pipeline", :problematic do
  let(:valid_payload) { { key: "value" }.to_json }
  let(:source) { "github" }
  let(:event_id) { "test-event-123" }
  let(:queue_adapter) { Queuing::SidekiqQueueAdapter.new }
  let(:worker_id) { "integration-test-worker" }

  describe "end-to-end event flow", :redis do
    before do
      # Ensure tests don't affect each other by clearing Redis queues
      clear_redis

      # Mock dependencies to avoid actual external calls while testing integration
      # between components
      allow(SecureRandom).to receive(:uuid).and_return(event_id)
      allow(queue_adapter).to receive(:with_redis).and_yield(redis_client)
    end

    after do
      # Clean up Redis after tests
      clear_redis
    end

    it "processes an event through the entire pipeline" do
      # Step 1: Queue a raw event (simulating EventsController)
      expect do
        queue_adapter.enqueue_raw_event(valid_payload, source)
      end.to change { queue_depth("queue:events:raw") }.by(1)

      # Step 2: Process the raw event batch (simulating RawEventProcessorJob)
      expect(queue_adapter).to receive(:get_next_batch).with(:raw_events).and_call_original

      # We're not testing the ProcessEvent use case here, just that it gets called with correct params
      process_event_use_case = instance_double(UseCases::ProcessEvent)
      allow(UseCaseFactory).to receive(:create_process_event).and_return(process_event_use_case)
      allow(process_event_use_case).to receive(:call).with(valid_payload, source: source)
                                                     .and_return(instance_double(Domain::Event, id: event_id))

      # Process the raw event
      processed = queue_adapter.process_raw_event_batch(worker_id)
      expect(processed).to eq(1)

      # Verify there are no more raw events
      expect(queue_depth("queue:events:raw")).to eq(0)
    end

    it "handles backpressure when queue is full" do
      # Mock the queue_depths method to simulate a full queue
      allow(queue_adapter).to receive(:queue_depths).and_return(
        raw_events: Queuing::SidekiqQueueAdapter::MAX_QUEUE_SIZE[:raw_events]
      )

      # The enqueue should raise a backpressure error
      expect do
        queue_adapter.enqueue_raw_event(valid_payload, source)
      end.to raise_error(Queuing::SidekiqQueueAdapter::QueueBackpressureError)
    end
  end

  describe "controller error handling", type: :request do
    it "handles JSON parsing errors in the controller" do
      # Setup controller test context
      @controller = Api::V1::EventsController.new
      allow(@controller).to receive(:authenticate_source!).and_return(true)

      # Send an invalid JSON payload
      invalid_payload = "{invalid_json"

      post "/api/v1/events", params: { source: source }, env: { "RAW_POST_DATA" => invalid_payload }

      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("Invalid JSON payload")
    end
  end

  private

  def clear_redis
    return unless redis_available?

    redis_client.keys("queue:*").each do |key|
      redis_client.del(key)
    end
  end

  def queue_depth(queue_name)
    return 0 unless redis_available?

    redis_client.llen(queue_name)
  end

  def redis_client
    @redis_client ||= begin
      Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    rescue Redis::CannotConnectError
      nil
    end
  end

  def redis_available?
    return @redis_available if defined?(@redis_available)

    return false unless redis_client

    begin
      redis_client.ping
      @redis_available = true
    rescue Redis::CannotConnectError
      @redis_available = false
    end

    @redis_available
  end
end
