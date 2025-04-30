module Api
  module V1
    class EventsController < ApplicationController
      # Disable CSRF for webhooks; use token auth instead
      skip_before_action :verify_authenticity_token
      before_action :authenticate_source!, only: [:create]

      def show
        use_case = UseCaseFactory.create_find_event
        event = use_case.call(params[:id])

        if event
          render json: event.to_h
        else
          render json: { error: "Event not found" }, status: :not_found
        end
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def create
        # Get the raw JSON payload and source parameter
        raw_payload = request.raw_post
        source = params.require(:source)

        # Log incoming request at debug level
        Rails.logger.debug { "EventsController#create received #{source} webhook" }

        begin
          # Quick validation of the payload (minimal processing)
          JSON.parse(raw_payload) # Just check if valid JSON

          # Get the queue adapter
          queue_adapter = DependencyContainer.resolve(:queue_port)

          # Enqueue the raw event for async processing
          event_id = SecureRandom.uuid
          enqueued = queue_adapter.enqueue_raw_event(raw_payload, source)

          if enqueued
            # Return 202 Accepted immediately - we'll process it asynchronously
            render json: {
              id: event_id,
              status: "accepted",
              message: "Event accepted for processing"
            }, status: :accepted
          else
            # Something went wrong with enqueuing
            render json: {
              error: "Unable to queue event for processing"
            }, status: :service_unavailable
          end
        rescue JSON::ParserError => e
          # Invalid JSON payload
          Rails.logger.error { "Invalid JSON payload: #{e.message}" }
          render json: { error: "Invalid JSON payload" }, status: :bad_request
        rescue Adapters::Queue::RedisQueueAdapter::QueueBackpressureError => e
          # Queue is experiencing backpressure
          Rails.logger.error { "Queue backpressure: #{e.message}" }
          render json: {
            error: "Service is under heavy load, please retry later",
            retry_after: 30
          }, status: :too_many_requests, headers: { "Retry-After": "30" }
        rescue ActionController::ParameterMissing => e
          # Missing required parameter
          Rails.logger.error { "Parameter missing: #{e.message}" }
          render json: { error: e.message }, status: :bad_request
        rescue StandardError => e
          # Unexpected error
          Rails.logger.error { "Error in EventsController#create: #{e.class.name} - #{e.message}" }
          Rails.logger.error { e.backtrace.join("\n") }
          render json: { error: "Internal server error" }, status: :internal_server_error
        end
      end

      private

      def authenticate_source!
        # Check for either X-Webhook-Token header or Bearer token in Authorization
        token = request.headers["X-Webhook-Token"] ||
                auth_header_token

        # Always allow in development/test mode
        return true if Rails.env.local?

        # Authenticate the token for the given source
        return if token && WebhookAuthenticator.valid?(token, params[:source])

        head :unauthorized
      end

      def auth_header_token
        # Extract token from Authorization: Bearer <token>
        auth_header = request.headers["Authorization"]
        return nil unless auth_header&.start_with?("Bearer ")

        auth_header.gsub("Bearer ", "")
      end
    end
  end
end
