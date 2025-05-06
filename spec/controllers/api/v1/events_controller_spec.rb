require "rails_helper"

RSpec.describe Api::V1::EventsController, type: :controller do
  let(:valid_token) { "test_token" }
  let(:github_payload) do
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
    }.to_json
  end

  let(:domain_event) do
    instance_double(
      Domain::Event,
      id: "event-123",
      source: "github",
      name: "github.push",
      timestamp: Time.current
    )
  end

  let(:find_event_use_case) { instance_double(UseCases::FindEvent) }
  let(:process_event_use_case) { instance_double(UseCases::ProcessEvent) }
  let(:queue_adapter) { instance_double(Queuing::SidekiqQueueAdapter) }
  let(:event_id) { "event-123" }

  before do
    # Mock the webhook authenticator
    allow(WebhookAuthenticator).to receive(:valid?).and_return(false)
    allow(WebhookAuthenticator).to receive(:valid?).with(valid_token, "github").and_return(true)

    # Set up the request body directly
    allow(request).to receive(:raw_post).and_return(github_payload)

    # Mock the use case factory and dependency container
    allow(UseCaseFactory).to receive(:create_find_event).and_return(find_event_use_case)
    allow(DependencyContainer).to receive(:resolve).with(:queue_port).and_return(queue_adapter)

    # For generating event IDs
    allow(SecureRandom).to receive(:uuid).and_return(event_id)
  end

  describe "POST #create" do
    context "with valid parameters and authentication" do
      before do
        # Set up headers
        request.headers["X-Webhook-Token"] = valid_token

        # Mock the queue adapter to accept events
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
        expect(json_response["message"]).to eq("Event accepted for processing")
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
        allow(request).to receive(:raw_post).and_return("{invalid json")
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

  describe "GET #show" do
    context "when the event exists" do
      before do
        allow(find_event_use_case).to receive(:call).with("event-123").and_return(domain_event)
        allow(domain_event).to receive(:to_h).and_return({ id: "event-123", source: "github", name: "github.push" })
      end

      it "returns a successful response" do
        get :show, params: { id: "event-123" }
        expect(response).to have_http_status(:ok)
      end

      it "returns the event data" do
        get :show, params: { id: "event-123" }
        json_response = JSON.parse(response.body)
        expect(json_response["id"]).to eq("event-123")
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
end
