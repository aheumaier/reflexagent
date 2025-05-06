# frozen_string_literal: true

require "rails_helper"

RSpec.describe Web::WebhooksController, type: :controller do
  # Set up routing for testing controllers in engines/adapters
  routes { Rails.application.routes }

  # Set controller name for the test
  controller(Web::WebhooksController) {}

  describe "POST #create" do
    let(:valid_payload) { { event: "push", repository: { name: "example" } }.to_json }
    let(:source) { "github" }

    before do
      # Mock the WebhookAuthentication methods since they are now in a concern
      allow(controller).to receive(:authenticate_webhook!).and_return(true)
      allow(controller).to receive(:validate_webhook_signature).and_return(true)

      # Mock receive_event to avoid calling the actual implementation
      allow(controller).to receive(:receive_event).and_return(true)

      # Set up the request
      request.headers["CONTENT_TYPE"] = "application/json"
      request.headers["X-Hub-Signature-256"] = "sha256=mock_signature"

      # Mock params to include source since it's not being passed correctly in the test
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(source: source))
    end

    it "accepts the webhook and returns 202 Accepted" do
      # Use process directly with action and parameters
      process :create, method: :post, params: { source: source }, body: valid_payload

      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)).to include("status" => "received")
    end

    it "processes the event using receive_event" do
      # Explicitly expect the source parameter
      expect(controller).to receive(:receive_event).with(valid_payload, source)

      process :create, method: :post, params: { source: source }, body: valid_payload
    end

    it "validates the signature if present" do
      # Explicitly expect the source parameter
      expect(controller).to receive(:validate_webhook_signature).with(valid_payload, "sha256=mock_signature", source)

      process :create, method: :post, params: { source: source }, body: valid_payload
    end

    context "when signature validation fails" do
      before do
        allow(controller).to receive(:validate_webhook_signature).and_return(false)
      end

      it "returns unauthorized status" do
        process :create, method: :post, params: { source: source }, body: valid_payload

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)).to include("error" => "Invalid signature")
      end
    end

    context "when an error occurs" do
      before do
        allow(controller).to receive(:receive_event).and_raise(StandardError.new("Test error"))
      end

      it "returns 500 error with message" do
        process :create, method: :post, params: { source: source }, body: valid_payload

        expect(response).to have_http_status(:internal_server_error)
        expect(JSON.parse(response.body)).to include("error" => "Test error")
      end
    end
  end

  describe "#receive_event" do
    it "logs event processing and returns true" do
      # This just tests the basic implementation
      expect(Rails.logger).to receive(:info)
      expect(controller.receive_event('{"type":"test"}', "github")).to be true
    end
  end
end
