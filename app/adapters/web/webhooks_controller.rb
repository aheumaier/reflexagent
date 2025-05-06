# frozen_string_literal: true

require_relative "../../ports/ingestion_port"

module Web
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_webhook!, only: [:create]

    include IngestionPort
    include WebhookAuthentication

    def create
      # Extract the payload and source
      payload = request.raw_post
      source = params[:source]

      Rails.logger.info("Received webhook from source: #{source}")

      # For GitHub webhooks, get all relevant headers
      if source == "github"
        github_headers = {}
        request.headers.each do |key, value|
          github_headers[key] = value if key.to_s.downcase.include?("github") ||
                                         key.to_s.downcase.include?("hub") ||
                                         key.to_s.downcase == "x-hub-signature" ||
                                         key.to_s.downcase == "x-hub-signature-256"
        end
        Rails.logger.info("GitHub webhook headers: #{github_headers.inspect}")
      end

      # Validate the signature if present
      signature = request.headers["X-Hub-Signature-256"] || request.headers["X-Hub-Signature"]

      if signature.present? && !validate_webhook_signature(payload, signature, source)
        Rails.logger.warn("Invalid webhook signature for source: #{source}")
        return render json: { error: "Invalid signature" }, status: :unauthorized
      end

      # Process the webhook payload
      receive_event(payload, source)

      render json: { status: "received" }, status: :accepted
    rescue StandardError => e
      Rails.logger.error("Webhook processing error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: e.message }, status: :internal_server_error
    end

    def receive_event(payload, source)
      # Implementation of IngestionPort#receive_event
      Rails.logger.info("Processing webhook event from #{source}")

      # Here you would normally process the event
      # This could involve parsing the payload and sending it to a use case

      # For debugging purposes
      begin
        parsed_payload = JSON.parse(payload)
        event_type = parsed_payload["type"] ||
                     parsed_payload["action"] ||
                     parsed_payload["event"] ||
                     (parsed_payload["ref"] && "push") ||
                     "unknown"
        Rails.logger.debug { "Event type: #{event_type}" }
      rescue JSON::ParserError => e
        Rails.logger.error("Failed to parse webhook payload: #{e.message}")
      end

      true # Return success
    end

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

    private

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

    def extract_token_from_authorization
      auth_header = request.headers["Authorization"]
      return nil unless auth_header&.start_with?("Bearer ")

      auth_header.gsub("Bearer ", "")
    end
  end
end
