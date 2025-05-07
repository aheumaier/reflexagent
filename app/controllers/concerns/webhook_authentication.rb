# frozen_string_literal: true

module WebhookAuthentication
  extend ActiveSupport::Concern

  included do
    # Skip CSRF for webhooks since we use token/signature auth instead
    skip_before_action :verify_authenticity_token, only: [:create]
  end

  # Class methods for the module
  class_methods do
    # Helper method to completely disable authentication in tests
    def disable_authentication_for_testing!
      return if method_defined?(:authenticate_webhook!)

      define_method(:authenticate_webhook!) do
        true
      end
    end
  end

  # Primary authentication method for webhooks
  # This replaces authenticate_source! from the controller
  def authenticate_webhook!
    # For tests, check if authentication has been globally disabled
    return true if Thread.current[:disable_webhook_auth]

    source = params[:source]

    # Log authentication attempt
    Rails.logger.info("Webhook authentication attempt for source: #{source}")

    # Always allow in development/test mode for easier testing
    return true if Rails.env.local?

    # For GitHub webhooks, use signature validation
    if source == "github"
      Rails.logger.info("GitHub webhook headers: #{relevant_github_headers.inspect}")

      # Check for signature headers - prefer SHA-256 over SHA-1
      signature_256 = request.headers["X-Hub-Signature-256"]
      signature_1 = request.headers["X-Hub-Signature"]

      if signature_256.present? || signature_1.present?
        result = validate_github_signature(
          request.raw_post,
          signature_256 || signature_1,
          source
        )

        unless result
          head :unauthorized
          return false
        end

        return true
      else
        Rails.logger.warn("No GitHub signature headers found")
      end
    end

    # For other sources, fall back to token authentication
    token = webhook_token

    # Token validation
    Rails.logger.info("Token present: #{!token.nil?}")
    Rails.logger.debug { "Authorization header present: #{!request.headers['Authorization'].nil?}" }
    Rails.logger.debug { "X-Webhook-Token header present: #{!request.headers['X-Webhook-Token'].nil?}" }

    # Authenticate the token for the given source
    is_valid = token && WebhookAuthenticator.valid?(token, source)

    unless is_valid
      Rails.logger.warn("Webhook authentication failed for source: #{source}")
      head :unauthorized
      return false
    end

    true
  end

  # Validate a GitHub webhook signature (SHA-256 or SHA-1)
  def validate_github_signature(payload, signature, source = "github")
    return true if Rails.env.local?

    # Get the webhook secret
    secret = WebhookAuthenticator.secret_for(source)

    if secret.nil?
      Rails.logger.warn("No GitHub webhook secret configured")
      return false
    end

    if signature.to_s.start_with?("sha256=")
      # SHA-256 validation
      expected = "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, payload)

      # Log signature details (first few chars only for security)
      Rails.logger.info("Validating GitHub SHA-256 signature")
      Rails.logger.debug { "Payload first 50 chars: #{payload[0..50]}..." }
      Rails.logger.debug { "Secret first 4 chars: #{secret[0..3]}..." if secret }
      Rails.logger.info("Signature comparison - Expected: #{expected[0..15]}... Received: #{signature[0..15]}...")

      # Use secure comparison to prevent timing attacks
      is_valid = Rack::Utils.secure_compare(expected, signature)

      Rails.logger.info("SHA-256 signature validation result: #{is_valid ? 'Valid' : 'Invalid'}")
      is_valid
    elsif signature.to_s.start_with?("sha1=")
      # SHA-1 validation (legacy)
      expected = "sha1=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha1"), secret, payload)

      # Log signature details
      Rails.logger.info("Validating GitHub SHA-1 signature (legacy)")
      Rails.logger.debug { "Payload first 50 chars: #{payload[0..50]}..." }
      Rails.logger.debug { "Secret first 4 chars: #{secret[0..3]}..." if secret }
      Rails.logger.info("Signature comparison - Expected: #{expected[0..15]}... Received: #{signature[0..15]}...")

      # Use secure comparison
      is_valid = Rack::Utils.secure_compare(expected, signature)

      Rails.logger.info("SHA-1 signature validation result: #{is_valid ? 'Valid' : 'Invalid'}")
      is_valid
    else
      # Unknown signature format
      Rails.logger.warn("Unknown GitHub signature format: #{signature[0..10]}...")
      false
    end
  end

  private

  # Helper method to extract the webhook token from headers
  def webhook_token
    request.headers["X-Webhook-Token"] || extract_token_from_authorization
  end

  # Extract the token from the Authorization header
  def extract_token_from_authorization
    auth_header = request.headers["Authorization"]
    return nil unless auth_header&.start_with?("Bearer ")

    auth_header.gsub("Bearer ", "")
  end

  # Helper method to store relevant headers for processing
  def store_webhook_headers
    Thread.current[:http_headers] = relevant_headers
  end

  # Get the relevant headers from the request
  def relevant_headers
    {
      "X-GitHub-Event" => request.headers["X-GitHub-Event"],
      "X-GitHub-Delivery" => request.headers["X-GitHub-Delivery"],
      "X-Hub-Signature" => request.headers["X-Hub-Signature"],
      "X-Hub-Signature-256" => request.headers["X-Hub-Signature-256"],
      "User-Agent" => request.headers["User-Agent"],
      "Content-Type" => request.headers["Content-Type"]
    }.compact
  end

  # Get GitHub-specific headers for logging
  def relevant_github_headers
    headers = {}
    headers["X-GitHub-Event"] = request.headers["X-GitHub-Event"] if request.headers["X-GitHub-Event"].present?
    headers["X-GitHub-Delivery"] = request.headers["X-GitHub-Delivery"] if request.headers["X-GitHub-Delivery"].present?
    headers
  end

  # Helper method to identify webhook endpoints
  def webhook_endpoint?
    params[:controller].end_with?("events_controller") && params[:action] == "create"
  end
end
