require "rails_helper"

RSpec.describe Api::V1::EventsController, type: :controller do
  include_context "webhook_testing"

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

  let(:github_payload) { github_payload_hash.to_json }
  let(:event_id) { "event-123" }

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

  let(:find_event_use_case) { instance_double(UseCases::FindEvent) }
  let(:queue_adapter) { instance_double(Queuing::SidekiqQueueAdapter) }

  before do
    # Set test payload directly on the controller instance var
    controller.instance_variable_set(:@_test_raw_post, github_payload)

    # Mock the webhook authenticator
    allow(WebhookAuthenticator).to receive(:valid?).and_return(false)
    allow(WebhookAuthenticator).to receive(:valid?).with(valid_token, "github").and_return(true)

    # Add JSON parse stubs
    allow(JSON).to receive(:parse).and_call_original
    allow(JSON).to receive(:parse).with(github_payload).and_return(github_payload_hash)

    # Simulate running in non-local environment for proper token checks
    allow(Rails.env).to receive(:local?).and_return(false)

    # For generating event IDs
    allow(SecureRandom).to receive(:uuid).and_return(event_id)
  end

  describe "GET #show" do
    before do
      # Set up use case factory
      allow(UseCaseFactory).to receive(:create_find_event).and_return(find_event_use_case)
    end

    context "when the event exists" do
      before do
        allow(find_event_use_case).to receive(:call).with(event_id).and_return(domain_event)
      end

      it "returns a successful response" do
        get :show, params: { id: event_id }
        expect(response).to have_http_status(:ok)
      end

      it "returns the event data" do
        get :show, params: { id: event_id }
        json_response = JSON.parse(response.body)
        expect(json_response["id"]).to eq(event_id)
        expect(json_response["source"]).to eq("github")
      end
    end

    context "when the event doesn't exist" do
      before do
        allow(find_event_use_case).to receive(:call).with("non-existent").and_return(nil)
      end

      it "returns a not found status" do
        get :show, params: { id: "non-existent" }
        expect(response).to have_http_status(:not_found)
      end

      it "includes an error message" do
        get :show, params: { id: "non-existent" }
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Event not found")
      end
    end

    context "when the use case raises an error" do
      before do
        allow(find_event_use_case).to receive(:call).with("error-id").and_raise(ArgumentError, "Invalid event ID")
      end

      it "returns an unprocessable entity status" do
        get :show, params: { id: "error-id" }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "includes the error message" do
        get :show, params: { id: "error-id" }
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Invalid event ID")
      end
    end
  end

  describe "POST #create" do
    before do
      allow(DependencyContainer).to receive(:resolve).with(:queue_port).and_return(queue_adapter)
    end

    context "with valid parameters and authentication" do
      before do
        request.headers["X-Webhook-Token"] = valid_token
        allow(queue_adapter).to receive(:enqueue_raw_event).with(github_payload, "github").and_return(true)
      end

      it "returns an accepted response" do
        post :create, params: { source: "github" }
        expect(response).to have_http_status(:accepted)
      end

      it "delegates to the queue adapter" do
        expect(queue_adapter).to receive(:enqueue_raw_event).with(github_payload, "github").and_return(true)
        post :create, params: { source: "github" }
      end

      it "returns the event ID and status" do
        post :create, params: { source: "github" }
        json_response = JSON.parse(response.body)
        expect(json_response["id"]).to eq(event_id)
        expect(json_response["status"]).to eq("accepted")
      end
    end

    context "with invalid authentication" do
      before do
        request.headers["X-Webhook-Token"] = "invalid_token"
      end

      it "returns an unauthorized status" do
        post :create, params: { source: "github" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with bearer token authentication" do
      before do
        request.headers["Authorization"] = "Bearer #{valid_token}"
        allow(queue_adapter).to receive(:enqueue_raw_event).with(github_payload, "github").and_return(true)
      end

      it "accepts a valid bearer token" do
        post :create, params: { source: "github" }
        expect(response).to have_http_status(:accepted)
      end
    end

    context "with invalid JSON payload" do
      before do
        request.headers["X-Webhook-Token"] = valid_token

        controller.instance_variable_set(:@_test_raw_post, "{invalid json")
        allow(JSON).to receive(:parse).with("{invalid json").and_raise(JSON::ParserError.new("Invalid JSON"))
      end

      it "returns a bad request status" do
        post :create, params: { source: "github" }
        expect(response).to have_http_status(:bad_request)
      end

      it "includes an error message" do
        post :create, params: { source: "github" }
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Invalid JSON payload")
      end
    end

    context "when the queue is experiencing backpressure" do
      before do
        request.headers["X-Webhook-Token"] = valid_token
        allow(queue_adapter).to receive(:enqueue_raw_event)
          .and_raise(Queuing::SidekiqQueueAdapter::QueueBackpressureError, "Queue is full")
      end

      it "returns a too many requests status" do
        post :create, params: { source: "github" }
        expect(response).to have_http_status(:too_many_requests)
      end

      it "includes a retry after header" do
        post :create, params: { source: "github" }
        expect(response.headers["Retry-After"]).to eq("30")
      end

      it "includes an error message with retry information" do
        post :create, params: { source: "github" }
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Service is under heavy load, please retry later")
        expect(json_response["retry_after"]).to eq(30)
      end
    end

    context "when the queue fails to enqueue the event" do
      before do
        request.headers["X-Webhook-Token"] = valid_token
        allow(queue_adapter).to receive(:enqueue_raw_event).and_return(false)
      end

      it "returns a service unavailable status" do
        post :create, params: { source: "github" }
        expect(response).to have_http_status(:service_unavailable)
      end

      it "includes an error message" do
        post :create, params: { source: "github" }
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Unable to queue event for processing")
      end
    end

    context "when an unexpected error occurs" do
      before do
        request.headers["X-Webhook-Token"] = valid_token
        allow(queue_adapter).to receive(:enqueue_raw_event).and_raise(StandardError, "Unexpected error")
      end

      it "returns an internal server error status" do
        post :create, params: { source: "github" }
        expect(response).to have_http_status(:internal_server_error)
      end

      it "includes a generic error message" do
        post :create, params: { source: "github" }
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Internal server error")
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).at_least(:once)
        post :create, params: { source: "github" }
      end
    end
  end
end
