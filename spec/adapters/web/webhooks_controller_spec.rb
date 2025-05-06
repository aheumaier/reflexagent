# frozen_string_literal: true

require "rails_helper"

RSpec.describe Web::WebhooksController, type: :controller do
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
    end

    it "accepts the webhook and returns 202 Accepted" do
      post :create, params: { source: source }, body: valid_payload

      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)).to include("status" => "received")
    end

    it "processes the event using receive_event" do
      expect(controller).to receive(:receive_event).with(valid_payload, source)

      post :create, params: { source: source }, body: valid_payload
    end

    it "validates the signature if present" do
      expect(controller).to receive(:validate_webhook_signature).with(valid_payload, "sha256=mock_signature", source)

      post :create, params: { source: source }, body: valid_payload
    end

    context "when signature validation fails" do
      before do
        allow(controller).to receive(:validate_webhook_signature).and_return(false)
      end

      it "returns unauthorized status" do
        post :create, params: { source: source }, body: valid_payload

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)).to include("error" => "Invalid signature")
      end
    end

    context "when an error occurs" do
      before do
        allow(controller).to receive(:receive_event).and_raise(StandardError.new("Test error"))
      end

      it "returns 500 error with message" do
        post :create, params: { source: source }, body: valid_payload

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
