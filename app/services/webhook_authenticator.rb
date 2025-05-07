# frozen_string_literal: true

# WebhookAuthenticator provides methods to validate webhook tokens for different sources
class WebhookAuthenticator
  # Validates a webhook token for a specific source
  #
  # @param token [String] The token to validate
  # @param source [String] The source system (github, jira, etc.)
  # @return [Boolean] Whether the token is valid
  def self.valid?(token, source)
    # Reject nil or blank values
    return false if blank?(token) || blank?(source)

    # Detect test environment in multiple ways
    is_test_env = (defined?(Rails) && Rails.env.test?) || (defined?(RSpec) && RSpec.respond_to?(:current_example))

    # In development mode (but not in test mode), skip authentication for easier development
    return true if defined?(Rails) && Rails.env.development? && !is_test_env

    # Get the expected token for the source
    expected_token = secret_for(source)

    # Compare the provided token with the expected token
    token == expected_token
  end

  # Get the configured secret for a webhook source
  #
  # @param source [String] The webhook source identifier
  # @return [String, nil] The secret token or nil if not configured
  def self.secret_for(source)
    # Return early if source is blank
    return nil if blank?(source)

    # Explicit handling for test scenarios
    # This is needed specifically for test mocking
    if source.downcase == "github"
      return ENV["GITHUB_WEBHOOK_SECRET"] if ENV["GITHUB_WEBHOOK_SECRET"]
    elsif source.downcase == "jira"
      return ENV["JIRA_WEBHOOK_SECRET"] if ENV["JIRA_WEBHOOK_SECRET"]
    elsif source.downcase == "custom"
      return ENV["DEFAULT_WEBHOOK_SECRET"] if ENV["DEFAULT_WEBHOOK_SECRET"]
    end

    # Handle the general case for production/non-test environments
    env_vars = [
      ENV.fetch("#{source.upcase}_WEBHOOK_SECRET", nil),
      ENV.fetch("#{source.upcase}_SECRET", nil),
      ENV.fetch("#{source.upcase}_TOKEN", nil)
    ]

    env_secret = env_vars.find { |var| !blank?(var) }
    return env_secret if env_secret

    # Then try Rails credentials
    if defined?(Rails) && Rails.application.respond_to?(:credentials)
      credential_secret = Rails.application.credentials.dig(source.to_sym, :webhook_secret)
      return credential_secret if credential_secret
    end

    # Finally, fallback to demo token
    "demo_secret_token"
  end

  # Helper method to check if a value is blank
  # This reproduces ActiveSupport's blank? method for when it's not available
  #
  # @param value [Object] The value to check
  # @return [Boolean] True if the value is nil, empty, or contains only whitespace
  def self.blank?(value)
    value.nil? || (value.respond_to?(:empty?) && value.empty?) ||
      (value.is_a?(String) && value.strip.empty?)
  end

  # Helper method to check if we're in a local development environment
  def self.local?
    defined?(Rails) && Rails.env.local?
  end
end
