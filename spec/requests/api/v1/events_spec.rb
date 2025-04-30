require "rails_helper"

RSpec.describe "API V1 Events", type: :request do
  describe "POST /api/v1/events" do
    let(:github_commit_payload) do
      {
        ref: "refs/heads/main",
        before: "6113728f27ae82c7b1a177c8d03f9e96e0adf246",
        after: "59b20b8d5c6ff8d09518216e87bc7ec123a3250a",
        repository: {
          id: 123_456,
          name: "ReflexAgent",
          full_name: "octocat/ReflexAgent",
          owner: {
            name: "octocat",
            email: "octocat@github.com"
          }
        },
        pusher: {
          name: "octocat",
          email: "octocat@github.com"
        },
        commits: [
          {
            id: "59b20b8d5c6ff8d09518216e87bc7ec123a3250a",
            message: "Add new feature for metric calculation",
            timestamp: "2023-06-15T12:00:00Z",
            author: {
              name: "Octocat",
              email: "octocat@github.com"
            }
          }
        ]
      }.to_json
    end

    let(:valid_headers) do
      {
        "Content-Type" => "application/json",
        "X-Webhook-Token" => "valid_token"
      }
    end

    before do
      # Mock the WebhookAuthenticator for all possible combinations
      allow(WebhookAuthenticator).to receive(:valid?).and_return(false)
      allow(WebhookAuthenticator).to receive(:valid?).with("valid_token", "github").and_return(true)

      allow(SecureRandom).to receive(:uuid).and_return("event-123")

      # Mock the queue port to avoid background job scheduling
      queue_port_double = double("QueuePort")
      allow(queue_port_double).to receive(:enqueue_raw_event).and_return(true)

      # Register our test doubles with the DependencyContainer
      DependencyContainer.register(:queue_port, queue_port_double)

      # Allow Rails.env.local? to return false in tests to force token validation
      allow(Rails.env).to receive(:local?).and_return(false)
    end

    context "with valid github commit payload" do
      it "accepts the webhook and returns a 202 status" do
        post "/api/v1/events?source=github",
             headers: valid_headers,
             env: { "RAW_POST_DATA" => github_commit_payload }

        expect(response).to have_http_status(:accepted)

        json_response = JSON.parse(response.body)
        expect(json_response["id"]).to eq("event-123")
        expect(json_response["status"]).to eq("accepted")
        expect(json_response["message"]).to eq("Event accepted for processing")
      end
    end

    context "with missing source parameter" do
      it "returns a 401 unauthorized status" do
        post "/api/v1/events",
             headers: valid_headers,
             env: { "RAW_POST_DATA" => github_commit_payload }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with invalid authentication token" do
      it "returns a 401 unauthorized status" do
        post "/api/v1/events?source=github",
             headers: { "Content-Type" => "application/json", "X-Webhook-Token" => "invalid_token" },
             env: { "RAW_POST_DATA" => github_commit_payload }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with bearer token authentication" do
      it "accepts the webhook with bearer token" do
        # Update the mock to handle this case
        allow(WebhookAuthenticator).to receive(:valid?).with("valid_token", "github").and_return(true)

        post "/api/v1/events?source=github",
             headers: {
               "Content-Type" => "application/json",
               "Authorization" => "Bearer valid_token"
             },
             env: { "RAW_POST_DATA" => github_commit_payload }

        expect(response).to have_http_status(:accepted)
      end
    end

    context "with invalid JSON payload" do
      it "returns a 400 bad request status" do
        # Need to stub authenticate_source! method to bypass authentication
        # before we get to JSON parsing error
        allow_any_instance_of(Api::V1::EventsController).to receive(:authenticate_source!).and_return(true)

        post "/api/v1/events?source=github",
             headers: valid_headers,
             env: { "RAW_POST_DATA" => "invalid json{" }

        expect(response).to have_http_status(:bad_request)

        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("Invalid JSON payload")
      end
    end
  end
end
