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

    expected_token = case source
                     when "github"
                       Rails.logger.info("GitHub webhook validation - Token received: #{token&.first(4)}*****")
                       github_token = ENV.fetch("GITHUB_WEBHOOK_TOKEN", nil)
                       Rails.logger.info("GitHub webhook validation - Expected token from ENV: #{github_token&.first(4)}*****")
                       Rails.logger.info("GitHub webhook ENV keys available: #{ENV.keys.grep(/GITHUB/).join(', ')}")
                       github_token
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

    is_valid = token == expected_token
    Rails.logger.info("Webhook authentication for #{source} - Result: #{is_valid ? 'Valid' : 'Invalid'}")
    is_valid
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
      # Log all environment variables related to GitHub to help debug
      github_env_vars = ENV.keys.grep(/GITHUB/).map { |k| "#{k}: #{ENV[k] ? 'set' : 'not set'}" }
      Rails.logger.info("All GitHub-related ENV variables: #{github_env_vars.join(', ')}")

      # Check specific environment variables
      github_secret = ENV.fetch("GITHUB_WEBHOOK_SECRET", nil)
      github_secret_key = ENV.fetch("GITHUB_WEBHOOK_SECRET_KEY", nil)
      github_secret_token = ENV.fetch("GITHUB_SECRET_TOKEN", nil)

      # Check credentials
      credential_secret = defined?(Rails) && Rails.application.try(:credentials).try(:dig, :github, :webhook_secret)

      # Log detailed information about all possible secret locations
      Rails.logger.info("GitHub webhook secret sources:")
      Rails.logger.info("- GITHUB_WEBHOOK_SECRET ENV: #{github_secret ? 'Present' : 'Missing'}")
      Rails.logger.info("- GITHUB_WEBHOOK_SECRET_KEY ENV: #{github_secret_key ? 'Present' : 'Missing'}")
      Rails.logger.info("- GITHUB_SECRET_TOKEN ENV: #{github_secret_token ? 'Present' : 'Missing'}")
      Rails.logger.info("- Rails credentials github.webhook_secret: #{credential_secret ? 'Present' : 'Missing'}")

      # Try all possible environment variable names
      secret = github_secret || github_secret_key || github_secret_token || credential_secret

      if secret
        Rails.logger.info("GitHub webhook secret found (first 4 chars): #{secret.first(4)}****")
        secret
      else
        Rails.logger.warn("No GitHub webhook secret found in any location, using demo_secret_token")
        "demo_secret_token"
      end
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
