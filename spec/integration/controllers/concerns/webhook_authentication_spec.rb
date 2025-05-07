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
        allow(controller.request).to receive(:raw_post).and_return('{"test":"data"}')
        # Mock validate_github_signature to return true for tests
        allow(controller).to receive(:validate_github_signature).and_return(true)
      end

      it "returns true when GitHub signature is present" do
        allow(Rails.env).to receive(:local?).and_return(false)
        expect(controller.authenticate_webhook!).to be true
      end

      it "logs a warning when no signature headers are present" do
        # Ensure we're not in local/dev mode for this test
        allow(Rails.env).to receive(:local?).and_return(false)

        # Reset headers to empty
        allow(controller.request).to receive(:headers).and_return({})

        # Explicitly stub webhook_token to return nil
        allow(controller).to receive(:webhook_token).and_return(nil)

        # WebhookAuthenticator.valid? will be called with nil token
        allow(WebhookAuthenticator).to receive(:valid?).with(nil, "github").and_return(false)

        # Now we expect the warning to be logged
        expect(Rails.logger).to receive(:warn).with("GitHub webhook received with no signature headers")

        # We also need to handle the second warning and render call
        expect(Rails.logger).to receive(:warn).with("Webhook authentication failed for source: github")
        expect(controller).to receive(:render).with(hash_including(status: :unauthorized))

        # Call should return false since authentication fails
        expect(controller.authenticate_webhook!).to be false
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
