# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::WebhooksController", :problematic, type: :request do
  # Include Rails testing helpers explicitly
  include ActionDispatch::IntegrationTest::Behavior
  include Rails.application.routes.url_helpers

  # Our webhooks_controller is a Rails controller that should be tested
  # as a request spec because we're testing the full HTTP request/response cycle

  describe "POST to webhooks endpoint" do
    let(:valid_payload) { { event: "push", repository: { name: "example" } }.to_json }
    let(:source) { "github" }
    let(:headers) do
      {
        "X-Hub-Signature-256" => "sha256=mock_signature"
      }
    end

    before do
      # Mock the webhook authentication
      allow_any_instance_of(Web::WebhooksController).to receive(:validate_webhook_signature).and_return(true)
      allow_any_instance_of(Web::WebhooksController).to receive(:authenticate_webhook!).and_return(true)
    end

    it "accepts the webhook and returns 202 Accepted" do
      post_json "/api/v1/events?source=#{source}",
                params: valid_payload,
                headers: headers

      expect(response).to have_http_status(:accepted)
      expect(json_response).to include("status" => "received")
    end

    context "when an error occurs" do
      before do
        # Force an error by providing invalid JSON
        @invalid_payload = "{ this is not valid JSON }"
      end

      it "returns an appropriate error response" do
        post_json "/api/v1/events?source=#{source}",
                  params: @invalid_payload,
                  headers: headers

        expect(response.status).to be >= 400
        expect(json_response).to have_key("error")
      end
    end
  end
end
