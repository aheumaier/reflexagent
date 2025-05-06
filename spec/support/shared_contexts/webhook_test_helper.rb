require "rails_helper"

# This module provides a shared context for testing webhook controllers that
# need to mock request.raw_post behavior in both controllers and requests specs
RSpec.shared_context "webhook_testing" do
  let(:valid_token) { "test_token" }

  # Create sample GitHub webhook payload
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

  # Setup helper to properly mock the raw_post behavior for controllers
  def setup_webhook_controller(controller, payload = github_payload, source = "github")
    # Mock token authenticator
    allow(WebhookAuthenticator).to receive(:valid?).and_return(false)
    allow(WebhookAuthenticator).to receive(:valid?).with(valid_token, source).and_return(true)

    # Set the test payload directly on the controller
    if defined?(controller) && controller.respond_to?(:instance_variable_set)
      controller.instance_variable_set(:@_test_raw_post, payload)
    end

    # Setup JSON parsing stubs
    allow(JSON).to receive(:parse).and_call_original
    if payload.is_a?(String)
      is_invalid = payload.include?("invalid")
      allow(JSON).to receive(:parse).with(payload).and_return(JSON.parse(payload)) unless is_invalid
    end

    # For generating event IDs
    allow(SecureRandom).to receive(:uuid).and_return(event_id)
  end

  def setup_bearer_auth(controller)
    return unless defined?(controller) && controller && defined?(controller.request)

    # For controller specs
    controller.request.headers["Authorization"] = "Bearer #{valid_token}"
  end

  def setup_token_auth(controller)
    return unless defined?(controller) && controller && defined?(controller.request)

    # For controller specs
    controller.request.headers["X-Webhook-Token"] = valid_token
  end
end
