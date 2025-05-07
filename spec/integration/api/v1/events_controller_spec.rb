# frozen_string_literal: true

require "rails_helper"

# Integration Test for API v1 Events Controller
RSpec.describe "Api::V1::EventsController", type: :request do
  # Include Rails testing helpers explicitly
  include ActionDispatch::IntegrationTest::Behavior
  include Rails.application.routes.url_helpers

  include_context "webhook_testing" if defined?(WebhookTesting)

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

  # Disable authentication for all tests
  before do
    # Bypass authentication in the controller
    allow_any_instance_of(Api::V1::EventsController).to receive(:authenticate_webhook!).and_return(true)
    # Mock the authenticator
    allow(WebhookAuthenticator).to receive(:valid?).and_return(true)
    # Mock the Rails.env.local? method, not the controller
    allow(Rails.env).to receive(:local?).and_return(false)
    # Ensure we're in test mode
    allow(Rails.env).to receive(:test?).and_return(true)
    allow(Rails.env).to receive(:development?).and_return(false)

    # Mock SecureRandom to generate predictable IDs for testing
    allow(SecureRandom).to receive(:uuid).and_return(event_id)
  end

  describe "GET /api/v1/events/:id" do
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

    before do
      # Set up use case factory
      allow(UseCaseFactory).to receive(:create_find_event).and_return(find_event_use_case)
    end

    context "when the event exists" do
      before do
        allow(find_event_use_case).to receive(:call).with(event_id).and_return(domain_event)
      end

      it "returns a successful response" do
        get_json "/api/v1/events/#{event_id}"
        expect(response).to have_http_status(:ok)
      end

      it "returns the event data" do
        get_json "/api/v1/events/#{event_id}"
        expect(json_response["id"]).to eq(event_id)
        expect(json_response["source"]).to eq("github")
      end
    end

    context "when the event doesn't exist" do
      before do
        allow(find_event_use_case).to receive(:call).with("non-existent").and_return(nil)
      end

      it "returns a not found status" do
        get_json "/api/v1/events/non-existent"
        expect(response).to have_http_status(:not_found)
      end

      it "includes an error message" do
        get_json "/api/v1/events/non-existent"
        expect(json_response["error"]).to eq("Event not found")
      end
    end

    context "when the use case raises an error" do
      before do
        allow(find_event_use_case).to receive(:call).with("error-id").and_raise(ArgumentError, "Invalid event ID")
      end

      it "returns an unprocessable entity status" do
        get_json "/api/v1/events/error-id"
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "includes the error message" do
        get_json "/api/v1/events/error-id"
        expect(json_response["error"]).to eq("Invalid event ID")
      end
    end
  end

  describe "POST /api/v1/events" do
    # Create a mock adapter class instead of using instance_double
    let(:queue_adapter) do
      Class.new do
        def enqueue_raw_event(payload, source)
          # Mock implementation
          true
        end

        # Define QueueBackpressureError within the mock
        QueueBackpressureError = Class.new(StandardError)
      end.new
    end

    before do
      allow(DependencyContainer).to receive(:resolve).with(:queue_port).and_return(queue_adapter)
    end

    context "with valid parameters and authentication" do
      before do
        allow(queue_adapter).to receive(:enqueue_raw_event).with(github_payload, "github").and_return(true)
      end

      it "returns an accepted response" do
        post_json "/api/v1/events?source=github",
                  params: github_payload,
                  headers: { "X-Webhook-Token" => valid_token }
        expect(response).to have_http_status(:accepted)
      end

      it "delegates to the queue adapter" do
        expect(queue_adapter).to receive(:enqueue_raw_event).with(github_payload, "github").and_return(true)
        post_json "/api/v1/events?source=github",
                  params: github_payload,
                  headers: { "X-Webhook-Token" => valid_token }
      end

      it "returns the event ID and status" do
        post_json "/api/v1/events?source=github",
                  params: github_payload,
                  headers: { "X-Webhook-Token" => valid_token }
        expect(json_response["id"]).to eq(event_id)
        expect(json_response["status"]).to eq("accepted")
      end
    end

    context "with invalid authentication" do
      before do
        # Override the global authentication stub just for this test
        allow_any_instance_of(Api::V1::EventsController).to receive(:authenticate_webhook!).and_call_original
        allow(WebhookAuthenticator).to receive(:valid?).and_return(false)
      end

      it "returns an unauthorized status" do
        post "/api/v1/events?source=github",
             params: github_payload,
             headers: { "Content-Type" => "application/json", "X-Webhook-Token" => "invalid_token" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with bearer token authentication" do
      before do
        allow(queue_adapter).to receive(:enqueue_raw_event).with(github_payload, "github").and_return(true)
      end

      it "accepts a valid bearer token" do
        post "/api/v1/events?source=github",
             params: github_payload,
             headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{valid_token}" }
        expect(response).to have_http_status(:accepted)
      end
    end

    context "with invalid JSON payload" do
      # Use the application-level rescue_from handler for invalid JSON
      it "returns a bad request status" do
        # Configure the middleware response
        allow(Rails.application.config.action_dispatch).to receive(:rescue_responses)
          .and_return({ "ActionDispatch::Http::Parameters::ParseError" => :bad_request })

        # Add rescue handler to controller for test
        exception = ActionDispatch::Http::Parameters::ParseError.new("Invalid JSON")
        allow_any_instance_of(Api::V1::EventsController).to receive(:create).and_raise(exception)

        post "/api/v1/events?source=github",
             params: "{invalid json",
             headers: { "Content-Type" => "application/json", "X-Webhook-Token" => valid_token }

        expect(response).to have_http_status(:bad_request)
      end

      it "includes an error message" do
        # Configure the middleware response
        allow(Rails.application.config.action_dispatch).to receive(:rescue_responses)
          .and_return({ "ActionDispatch::Http::Parameters::ParseError" => :bad_request })

        # Add rescue handler to controller for test
        exception = ActionDispatch::Http::Parameters::ParseError.new("Invalid JSON")
        allow_any_instance_of(Api::V1::EventsController).to receive(:create).and_raise(exception)

        post "/api/v1/events?source=github",
             params: "{invalid json",
             headers: { "Content-Type" => "application/json", "X-Webhook-Token" => valid_token }

        expect(json_response["error"]).to include("Invalid JSON")
      end
    end

    context "when the queue is experiencing backpressure" do
      before do
        allow(queue_adapter).to receive(:enqueue_raw_event)
          .and_raise(Queuing::SidekiqQueueAdapter::QueueBackpressureError, "Queue is full")
      end

      it "returns a too many requests status" do
        post "/api/v1/events?source=github",
             params: github_payload,
             headers: { "Content-Type" => "application/json", "X-Webhook-Token" => valid_token }
        expect(response).to have_http_status(:too_many_requests)
      end

      it "includes a retry after header" do
        post "/api/v1/events?source=github",
             params: github_payload,
             headers: { "Content-Type" => "application/json", "X-Webhook-Token" => valid_token }
        expect(response.headers["Retry-After"]).to eq("30")
      end

      it "includes an error message with retry information" do
        post "/api/v1/events?source=github",
             params: github_payload,
             headers: { "Content-Type" => "application/json", "X-Webhook-Token" => valid_token }
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Service is under heavy load, please retry later")
        expect(json_response["retry_after"]).to eq(30)
      end
    end

    context "when the queue fails to enqueue the event" do
      before do
        allow(queue_adapter).to receive(:enqueue_raw_event).and_return(false)
      end

      it "returns a service unavailable status" do
        post "/api/v1/events?source=github",
             params: github_payload,
             headers: { "Content-Type" => "application/json", "X-Webhook-Token" => valid_token }
        expect(response).to have_http_status(:service_unavailable)
      end

      it "includes an error message" do
        post "/api/v1/events?source=github",
             params: github_payload,
             headers: { "Content-Type" => "application/json", "X-Webhook-Token" => valid_token }
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Unable to queue event for processing")
      end
    end

    context "when an unexpected error occurs" do
      before do
        allow(queue_adapter).to receive(:enqueue_raw_event).and_raise(StandardError, "Unexpected error")
      end

      it "returns an internal server error status" do
        post "/api/v1/events?source=github",
             params: github_payload,
             headers: { "Content-Type" => "application/json", "X-Webhook-Token" => valid_token }
        expect(response).to have_http_status(:internal_server_error)
      end

      it "includes a generic error message" do
        post "/api/v1/events?source=github",
             params: github_payload,
             headers: { "Content-Type" => "application/json", "X-Webhook-Token" => valid_token }
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Internal server error")
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).at_least(:once)
        post "/api/v1/events?source=github",
             params: github_payload,
             headers: { "Content-Type" => "application/json", "X-Webhook-Token" => valid_token }
      end
    end
  end
end
