# frozen_string_literal: true

require_relative "../../ports/ingestion_port"

module Web
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token

    include IngestionPort

    def create
      # This is a placeholder implementation
      # In a real application, this would deserialize the webhook payload
      # and call the ProcessEvent use case

      render json: { status: "received" }, status: :accepted
    end

    def receive_event(payload)
      # Implementation of IngestionPort#receive_event
    end

    def validate_webhook_signature(payload, signature)
      # Implementation of IngestionPort#validate_webhook_signature
      true # Placeholder implementation
    end
  end
end
