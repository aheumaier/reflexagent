# frozen_string_literal: true

# Helper module to disable webhook authentication in tests
module WebhookAuthenticationTestHelper
  def self.included(base)
    base.before do
      # Ensure we're in test mode
      allow(Rails.env).to receive(:test?).and_return(true)
      allow(Rails.env).to receive(:development?).and_return(false)

      # Option 1: Set Rails.env.local? to true to bypass authentication
      allow(Rails.env).to receive(:local?).and_return(true)

      # Option 2: Set the global Thread variable to disable authentication
      Thread.current[:disable_webhook_auth] = true

      # Option 3: Mock environment variables for token authentication
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GITHUB_WEBHOOK_SECRET").and_return("test_token")
      allow(ENV).to receive(:[]).with("JIRA_WEBHOOK_SECRET").and_return("test_token")
      allow(ENV).to receive(:[]).with("DEFAULT_WEBHOOK_SECRET").and_return("test_token")

      # Option 4: Mock the WebhookAuthenticator.valid? method directly
      allow(WebhookAuthenticator).to receive(:valid?).and_return(true)

      # Option 5: Mock controller authentication methods
      # Preload needed controller classes for allow_any_instance_of to work
      if defined?(Api::V1::EventsController)
        Api::V1::EventsController
        allow_any_instance_of(Api::V1::EventsController).to receive(:authenticate_webhook!).and_return(true)
      end

      # Clean up after tests
      base.after do
        Thread.current[:disable_webhook_auth] = nil
      end
    end
  end

  # Helper method to add authentication to a request
  def with_webhook_auth(source = "github")
    # Add the X-Webhook-Token header with a test token
    {
      "X-Webhook-Token" => "test_token",
      "Content-Type" => "application/json"
    }
  end

  # Helper method to add GitHub signature authentication
  def with_github_signature(payload, source = "github")
    secret = "test_token"
    signature = "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, payload)

    {
      "X-Hub-Signature-256" => signature,
      "Content-Type" => "application/json"
    }
  end
end
