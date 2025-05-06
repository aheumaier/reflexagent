require "rails_helper"

RSpec.describe "Events API", type: :request do
  let(:valid_token) { "test_token" }
  let(:github_payload_hash) do
    {
      ref: "refs/heads/main",
      repository: {
        full_name: "test/repo"
      },
      commits: [
        {
          id: "abc123",
          message: "Test commit"
        }
      ]
    }
  end
  let(:event_id) { "event-123" }

  before do
    # Enable test mode for webhook authentication
    allow(Rails.env).to receive(:local?).and_return(true)

    # For generating event IDs
    allow(SecureRandom).to receive(:uuid).and_return(event_id)

    # Replace the queue adapter for testing
    queue_adapter = instance_double(Queuing::SidekiqQueueAdapter)
    allow(DependencyContainer).to receive(:resolve).with(:queue_port).and_return(queue_adapter)

    # Default behavior for queue adapter (can be overridden in specific tests)
    allow(queue_adapter).to receive(:enqueue_raw_event).and_return(true)
  end

  describe "POST /api/v1/events" do
    it "accepts the webhook with valid parameters" do
      post "/api/v1/events?source=github",
           as: :json,
           params: github_payload_hash

      expect(response).to have_http_status(:accepted)

      json_response = JSON.parse(response.body)
      expect(json_response["id"]).to eq(event_id)
      expect(json_response["status"]).to eq("accepted")
    end

    context "when the queue adapter experiences backpressure" do
      before do
        queue_adapter = instance_double(Queuing::SidekiqQueueAdapter)
        allow(DependencyContainer).to receive(:resolve).with(:queue_port).and_return(queue_adapter)
        allow(queue_adapter).to receive(:enqueue_raw_event)
          .and_raise(Queuing::SidekiqQueueAdapter::QueueBackpressureError, "Queue is full")
      end

      it "returns a too many requests status with retry information" do
        post "/api/v1/events?source=github",
             as: :json,
             params: github_payload_hash

        expect(response).to have_http_status(:too_many_requests)

        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Service is under heavy load, please retry later")
        expect(json_response["retry_after"]).to eq(30)
      end
    end
  end

  describe "GET /api/v1/events/:id" do
    context "when the event exists" do
      let(:domain_event) do
        instance_double(
          Domain::Event,
          id: event_id,
          source: "github",
          name: "github.push",
          timestamp: Time.current,
          to_h: { id: event_id, source: "github", name: "github.push" }
        )
      end

      before do
        find_event_use_case = instance_double(UseCases::FindEvent)
        allow(UseCaseFactory).to receive(:create_find_event).and_return(find_event_use_case)
        allow(find_event_use_case).to receive(:call).with(event_id).and_return(domain_event)
      end

      it "returns 200 and the event data" do
        get "/api/v1/events/#{event_id}"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["id"]).to eq(event_id)
        expect(json["source"]).to eq("github")
      end
    end

    context "when the event doesn't exist" do
      before do
        find_event_use_case = instance_double(UseCases::FindEvent)
        allow(UseCaseFactory).to receive(:create_find_event).and_return(find_event_use_case)
        allow(find_event_use_case).to receive(:call).with("non-existent").and_return(nil)
      end

      it "returns 404" do
        get "/api/v1/events/non-existent"

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Event not found")
      end
    end
  end
end
