# frozen_string_literal: true

module WebhookAuthentication
  extend ActiveSupport::Concern

  included do
    # Any class methods needed
  end

  # Validate the webhook signature
  def validate_webhook_signature(payload, signature, source)
    # Implementation of IngestionPort#validate_webhook_signature
    Rails.logger.info("Validating webhook signature for source: #{source}")

    # Get the secret for this source
    secret = WebhookAuthenticator.secret_for(source)

    if secret.nil?
      Rails.logger.warn("No webhook secret configured for source: #{source}")
      return false
    end

    # For GitHub webhooks, verify the signature
    if source == "github" && signature.present?
      # GitHub prefers SHA-256 over SHA-1
      if signature.start_with?("sha256=")
        # SHA-256 signature validation
        expected_signature = "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, payload)

        # Log signature details (first few chars only for security)
        Rails.logger.info("Validating GitHub SHA-256 signature")
        Rails.logger.debug { "Payload first 50 chars: #{payload[0..50]}..." }
        Rails.logger.debug { "Secret first 4 chars: #{secret[0..3]}..." }
        Rails.logger.info("Signature comparison - Expected: #{expected_signature[0..15]}... Received: #{signature[0..15]}...")

        # Use secure comparison to prevent timing attacks as recommended by GitHub
        result = Rack::Utils.secure_compare(expected_signature, signature)
        Rails.logger.info("SHA-256 signature validation result: #{result ? 'Valid' : 'Invalid'}")
        return result
      elsif signature.start_with?("sha1=")
        # SHA-1 signature validation (legacy)
        expected_signature = "sha1=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha1"), secret, payload)

        # Log signature details
        Rails.logger.info("Validating GitHub SHA-1 signature (legacy)")
        Rails.logger.debug { "Payload first 50 chars: #{payload[0..50]}..." }
        Rails.logger.debug { "Secret first 4 chars: #{secret[0..3]}..." }
        Rails.logger.info("Signature comparison - Expected: #{expected_signature[0..15]}... Received: #{signature[0..15]}...")

        # Use secure comparison
        result = Rack::Utils.secure_compare(expected_signature, signature)
        Rails.logger.info("SHA-1 signature validation result: #{result ? 'Valid' : 'Invalid'}")
        return result
      else
        # Unknown signature format
        Rails.logger.warn("Unknown GitHub signature format: #{signature[0..10]}...")
        return false
      end
    end

    # For other sources, implement appropriate signature validation
    # or return true if signature validation is not required
    true
  end

  # Authenticate the webhook request
  def authenticate_webhook!
    token = request.headers["X-Webhook-Token"] ||
            extract_token_from_authorization

    source = params[:source]

    Rails.logger.info("Authenticating webhook from source: #{source}")

    # GitHub uses signature-based authentication
    if source == "github"
      signature = request.headers["X-Hub-Signature-256"] || request.headers["X-Hub-Signature"]

      if signature.present?
        # We'll validate the signature in the validate_webhook_signature method
        return true
      end

      Rails.logger.warn("GitHub webhook received with no signature headers")
    end

    # Skip authentication in development
    return true if Rails.env.local?

    unless token && WebhookAuthenticator.valid?(token, source)
      Rails.logger.warn("Webhook authentication failed for source: #{source}")
      render json: { error: "Unauthorized" }, status: :unauthorized
      return false
    end

    true
  end

  private

  # Extract the token from the Authorization header
  def extract_token_from_authorization
    auth_header = request.headers["Authorization"]
    return nil unless auth_header&.start_with?("Bearer ")

    auth_header.gsub("Bearer ", "")
  end
end
