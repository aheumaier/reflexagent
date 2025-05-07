# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookAuthentication, type: :concern do
  let(:controller_class) do
    Class.new(ActionController::Base) do
      include WebhookAuthentication

      def request
        @request ||= ActionDispatch::TestRequest.create
      end

      def params
        @params ||= ActionController::Parameters.new(source: "github")
      end

      def render(options)
        # Just a stub to avoid actual rendering
        @render_options = options
      end
    end
  end

  let(:controller) { controller_class.new }

  describe "#authenticate_webhook!" do
    context "with GitHub webhooks" do
      before do
        allow(controller.request).to receive(:headers).and_return(
          "X-Hub-Signature-256" => "sha256=abc123"
        )
      end

      it "returns true when GitHub signature is present" do
        expect(controller.authenticate_webhook!).to be true
      end

      it "logs a warning when no signature headers are present" do
        allow(controller.request).to receive(:headers).and_return({})
        expect(Rails.logger).to receive(:warn).with("GitHub webhook received with no signature headers")
        controller.authenticate_webhook!
      end
    end

    context "with token authentication" do
      before do
        allow(controller).to receive(:params).and_return(ActionController::Parameters.new(source: "jira"))
        allow(Rails.env).to receive(:local?).and_return(false)
      end

      it "authenticates with valid token in X-Webhook-Token header" do
        allow(controller.request).to receive(:headers).and_return(
          "X-Webhook-Token" => "valid_token"
        )
        allow(WebhookAuthenticator).to receive(:valid?).with("valid_token", "jira").and_return(true)

        expect(controller.authenticate_webhook!).to be true
      end

      it "authenticates with valid token in Authorization header" do
        allow(controller.request).to receive(:headers).and_return(
          "Authorization" => "Bearer valid_token"
        )
        allow(WebhookAuthenticator).to receive(:valid?).with("valid_token", "jira").and_return(true)

        expect(controller.authenticate_webhook!).to be true
      end

      it "returns unauthorized for invalid token" do
        allow(controller.request).to receive(:headers).and_return(
          "X-Webhook-Token" => "invalid_token"
        )
        allow(WebhookAuthenticator).to receive(:valid?).with("invalid_token", "jira").and_return(false)

        expect(Rails.logger).to receive(:warn)
        expect(controller).to receive(:render).with(hash_including(status: :unauthorized))
        expect(controller.authenticate_webhook!).to be false
      end
    end

    context "in local environment" do
      before do
        allow(Rails.env).to receive(:local?).and_return(true)
      end

      it "skips authentication" do
        expect(controller.authenticate_webhook!).to be true
      end
    end
  end

  describe "#validate_webhook_signature" do
    let(:payload) { '{"key":"value"}' }
    let(:secret) { "webhook_secret" }

    before do
      allow(WebhookAuthenticator).to receive(:secret_for).with("github").and_return(secret)
      allow(WebhookAuthenticator).to receive(:secret_for).with("jira").and_return("jira_secret")
    end

    context "with GitHub SHA-256 signature" do
      let(:signature) { "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, payload) }

      it "returns true for valid signature" do
        expect(controller.validate_webhook_signature(payload, signature, "github")).to be true
      end

      it "returns false for invalid signature" do
        expect(controller.validate_webhook_signature(payload, "sha256=invalid", "github")).to be false
      end
    end

    context "with GitHub SHA-1 signature" do
      let(:signature) { "sha1=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha1"), secret, payload) }

      it "returns true for valid signature" do
        expect(controller.validate_webhook_signature(payload, signature, "github")).to be true
      end

      it "returns false for invalid signature" do
        expect(controller.validate_webhook_signature(payload, "sha1=invalid", "github")).to be false
      end
    end

    context "with unknown signature format" do
      it "returns false for unknown format" do
        expect(controller.validate_webhook_signature(payload, "unknown=format", "github")).to be false
      end
    end

    context "with no secret configured" do
      before do
        allow(WebhookAuthenticator).to receive(:secret_for).with("github").and_return(nil)
      end

      it "returns false when no secret is configured" do
        expect(controller.validate_webhook_signature(payload, "sha256=whatever", "github")).to be false
      end
    end

    context "with non-GitHub source" do
      it "returns true for other sources" do
        expect(controller.validate_webhook_signature(payload, "some-signature", "jira")).to be true
      end
    end
  end
end
