# frozen_string_literal: true

# Helper module to disable webhook authentication in tests
module WebhookAuthenticationTestHelper
  def self.included(base)
    base.before do
      # Mock the Rails environment to bypass environment-specific auth
      allow(Rails.env).to receive(:local?).and_return(true)

      # This bypasses the authentication method in controllers
      # Need to preload the controller class for allow_any_instance_of to work in request specs
      Api::V1::EventsController
      allow_any_instance_of(Api::V1::EventsController).to receive(:authenticate_webhook!).and_return(true)
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
end
