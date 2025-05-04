# frozen_string_literal: true

require_relative "../../ports/ingestion_port"

module Web
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_webhook!, only: [:create]

    include IngestionPort

    def create
      # Extract the payload and source
      payload = request.raw_post
      source = params[:source]

      Rails.logger.info("Received webhook from source: #{source}")

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
        Rails.logger.debug { "Event type: #{parsed_payload['type'] || parsed_payload['action'] || 'unknown'}" }
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
        # GitHub uses HMAC SHA-256 for X-Hub-Signature-256 or HMAC SHA-1 for X-Hub-Signature
        if signature.start_with?("sha256=")
          # SHA-256 signature
          digest = OpenSSL::Digest.new("sha256")
          signature_type = "sha256="
        else
          # SHA-1 signature (legacy)
          digest = OpenSSL::Digest.new("sha1")
          signature_type = "sha1="
        end

        # Calculate expected signature
        hmac = OpenSSL::HMAC.hexdigest(digest, secret, payload)
        expected_signature = "#{signature_type}#{hmac}"

        # Compare signatures
        Rails.logger.info("Signature comparison - Expected: #{expected_signature[0..15]}... Received: #{signature[0..15]}...")
        return ActiveSupport::SecurityUtils.secure_compare(expected_signature, signature)
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
