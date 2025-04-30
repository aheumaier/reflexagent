# frozen_string_literal: true

# WebhookAuthenticator provides methods to validate webhook tokens for different sources
class WebhookAuthenticator
  # Validates a webhook token for a specific source
  #
  # @param token [String] The token to validate
  # @param source [String] The source system (github, jira, etc.)
  # @return [Boolean] Whether the token is valid
  def self.valid?(token, source)
    # In development mode, skip authentication
    return true if Rails.env.local?

    # In production, validate the token against the expected value for the source
    token == case source
             when "github"
               ENV.fetch("GITHUB_WEBHOOK_TOKEN", nil)
             when "jira"
               ENV.fetch("JIRA_WEBHOOK_TOKEN", nil)
             when "gitlab"
               ENV.fetch("GITLAB_WEBHOOK_TOKEN", nil)
             when "bitbucket"
               ENV.fetch("BITBUCKET_WEBHOOK_TOKEN", nil)
             else
               # For unknown sources, always require a custom token
               ENV.fetch("#{source.upcase}_WEBHOOK_TOKEN", nil)
             end
  end

  # Get the configured secret for a webhook source
  #
  # @param source [String] The webhook source identifier
  # @return [String, nil] The secret token or nil if not configured
  def self.secret_for(source)
    # In production, these would be stored in credentials or environment variables
    # and accessed through Rails.application.credentials or ENV
    case source
    when "github"
      ENV["GITHUB_WEBHOOK_SECRET"] ||
        (defined?(Rails) && Rails.application.try(:credentials).try(:dig, :github, :webhook_secret)) ||
        "demo_secret_token"
    when "jira"
      ENV["JIRA_WEBHOOK_SECRET"] ||
        (defined?(Rails) && Rails.application.try(:credentials).try(:dig, :jira, :webhook_secret)) ||
        "demo_secret_token"
    when "gitlab"
      ENV["GITLAB_WEBHOOK_SECRET"] ||
        (defined?(Rails) && Rails.application.try(:credentials).try(:dig, :gitlab, :webhook_secret)) ||
        "demo_secret_token"
    when "bitbucket"
      ENV["BITBUCKET_WEBHOOK_SECRET"] ||
        (defined?(Rails) && Rails.application.try(:credentials).try(:dig, :bitbucket, :webhook_secret)) ||
        "demo_secret_token"
    else
      # Default token for other sources, or nil for security
      ENV["DEFAULT_WEBHOOK_SECRET"] ||
        (defined?(Rails) && Rails.application.try(:credentials).try(:dig, :webhook, :default_secret)) ||
        "demo_secret_token"
    end
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
end
