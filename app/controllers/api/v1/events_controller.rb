module Api
  module V1
    class EventsController < ApplicationController
      include IngestionPort
      include WebhookAuthentication

      # CSRF is now handled in the WebhookAuthentication concern
      before_action :authenticate_webhook!, only: [:create, :show]
      before_action :store_webhook_headers, only: [:create]

      # Add handler for invalid JSON
      rescue_from ActionDispatch::Http::Parameters::ParseError do |exception|
        render json: { error: "Invalid JSON payload" }, status: :bad_request
      end

      # Implement IngestionPort#receive_event
      def receive_event(raw_payload, source:)
        # This method implements the IngestionPort interface
        # Parse the raw payload and create a domain event

        # Validate JSON first
        JSON.parse(raw_payload)

        # Use the WebAdapter to process the event
        web_adapter = DependencyContainer.resolve(:ingestion_port)
        web_adapter.receive_event(raw_payload, source: source)
      rescue JSON::ParserError => e
        Rails.logger.error { "Invalid JSON payload: #{e.message}" }
        raise "Invalid JSON payload"
      end

      # Implementation of IngestionPort interface, delegating to the concern
      def validate_webhook_signature(payload, signature, source = nil)
        validate_github_signature(payload, signature, source || params[:source])
      end

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
        raw_payload = get_raw_payload
        source = params.require(:source)

        # Log incoming request at debug level
        Rails.logger.debug { "EventsController#create received #{source} webhook" }
        Rails.logger.debug { "Raw payload: #{raw_payload.blank? ? 'BLANK' : raw_payload[0..100]}" }

        # Log which headers we have for GitHub webhooks
        if source == "github"
          Rails.logger.info("GitHub webhook received with headers: #{relevant_github_headers.inspect}")
        end

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
        rescue Queuing::SidekiqQueueAdapter::QueueBackpressureError => e
          # Queue is experiencing backpressure
          Rails.logger.error { "Queue backpressure: #{e.message}" }
          response.headers["Retry-After"] = "30"
          render json: {
            error: "Service is under heavy load, please retry later",
            retry_after: 30
          }, status: :too_many_requests
        rescue ActionController::ParameterMissing => e
          # Missing required parameter
          Rails.logger.error { "Parameter missing: #{e.message}" }
          render json: { error: e.message }, status: :bad_request
        rescue StandardError => e
          # Unexpected error
          Rails.logger.error { "Error in EventsController#create: #{e.class.name} - #{e.message}" }
          Rails.logger.error { e.backtrace.join("\n") }
          render json: { error: "Internal server error" }, status: :internal_server_error
        ensure
          # Clear thread-local headers after processing
          Thread.current[:http_headers] = nil
        end
      end

      private

      # Helper method to get raw payload with better test support
      def get_raw_payload
        # First check for a special test instance variable (for controller specs)
        return @_test_raw_post if defined?(@_test_raw_post) && @_test_raw_post.present?

        # Then check for a webhook param (for request specs)
        if params[:webhook].present?
          return params[:webhook].is_a?(String) ? params[:webhook] : params[:webhook].to_json
        end

        # Finally use the actual raw_post from the request
        request.raw_post
      end
    end
  end
end
