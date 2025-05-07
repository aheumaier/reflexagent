module Api
  module V1
    class EventsController < ApplicationController
      include IngestionPort

      # Disable CSRF for webhooks; use token auth instead
      skip_before_action :verify_authenticity_token
      before_action :authenticate_source!, only: [:create]
      before_action :store_headers, only: [:create]

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

      # Implement IngestionPort#validate_webhook_signature
      def validate_webhook_signature(payload, signature)
        return true if Rails.env.local?

        # Currently relying on authenticate_source! for validation
        # This method provides a standard interface for signature validation
        if signature.to_s.start_with?("sha256=")
          # SHA-256 validation
          secret = WebhookAuthenticator.secret_for("github")
          return false unless secret

          expected = "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, payload)
          Rack::Utils.secure_compare(expected, signature)
        elsif signature.to_s.start_with?("sha1=")
          # SHA-1 validation
          secret = WebhookAuthenticator.secret_for("github")
          return false unless secret

          expected = "sha1=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha1"), secret, payload)
          Rack::Utils.secure_compare(expected, signature)
        else
          # Token-based validation
          WebhookAuthenticator.valid?(signature, params[:source])
        end
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

      def store_headers
        # Store relevant headers in thread-local storage for the adapter to access
        Thread.current[:http_headers] = relevant_headers
      end

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

      def relevant_github_headers
        headers = {}
        headers["X-GitHub-Event"] = request.headers["X-GitHub-Event"] if request.headers["X-GitHub-Event"].present?
        if request.headers["X-GitHub-Delivery"].present?
          headers["X-GitHub-Delivery"] =
            request.headers["X-GitHub-Delivery"]
        end
        headers
      end

      def authenticate_source!
        source = params[:source]

        # Log authentication attempt
        Rails.logger.info("Webhook authentication attempt for source: #{source}")

        # Always allow in development/test mode
        return true if Rails.env.local?

        # For GitHub webhooks, use signature validation
        if source == "github"
          Rails.logger.info("GitHub webhook headers: #{relevant_github_headers.inspect}")

          # Check for signature headers - prefer SHA-256 over SHA-1
          signature = request.headers["X-Hub-Signature-256"]

          Rails.logger.info("GitHub SHA-256 signature present: #{!signature.nil?}")

          if signature.present?
            # Get the webhook secret
            secret = WebhookAuthenticator.secret_for("github")

            if secret.nil?
              Rails.logger.warn("No GitHub webhook secret configured")
              head :unauthorized
              return false
            end

            # Get raw payload
            payload = request.raw_post

            # Verify the signature using HMAC-SHA256
            expected_signature = "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, payload)

            # Log signature details (first 10 chars only for security)
            Rails.logger.info("Signature comparison - Expected: #{expected_signature[0..15]}... Received: #{signature[0..15]}...")

            # Use secure comparison to prevent timing attacks
            is_valid = Rack::Utils.secure_compare(expected_signature, signature)

            unless is_valid
              Rails.logger.warn("GitHub signature validation failed")
              head :unauthorized
              return false
            end

            Rails.logger.info("GitHub signature validation successful")
            return true
          else
            # Fall back to SHA-1 for legacy support
            signature = request.headers["X-Hub-Signature"]

            if signature.present?
              Rails.logger.info("Falling back to SHA-1 signature validation")

              # Get the webhook secret
              secret = WebhookAuthenticator.secret_for("github")

              if secret.nil?
                Rails.logger.warn("No GitHub webhook secret configured")
                head :unauthorized
                return false
              end

              # Get raw payload
              payload = request.raw_post

              # Verify the signature using HMAC-SHA1
              expected_signature = "sha1=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha1"), secret, payload)

              # Log signature details (first 10 chars only for security)
              Rails.logger.info("Signature comparison - Expected: #{expected_signature[0..15]}... Received: #{signature[0..15]}...")

              # Use secure comparison to prevent timing attacks
              is_valid = Rack::Utils.secure_compare(expected_signature, signature)

              unless is_valid
                Rails.logger.warn("GitHub SHA-1 signature validation failed")
                head :unauthorized
                return false
              end

              Rails.logger.info("GitHub SHA-1 signature validation successful")
              return true
            else
              Rails.logger.warn("No GitHub signature headers found")
            end
          end
        end

        # For other sources, fall back to token authentication
        token = request.headers["X-Webhook-Token"] ||
                auth_header_token

        Rails.logger.info("Token present: #{!token.nil?}")
        Rails.logger.info("Authorization header present: #{!request.headers['Authorization'].nil?}")
        Rails.logger.info("X-Webhook-Token header present: #{!request.headers['X-Webhook-Token'].nil?}")

        # Authenticate the token for the given source
        is_valid = token && WebhookAuthenticator.valid?(token, source)

        unless is_valid
          Rails.logger.warn("Webhook authentication failed for source: #{source}")
          head :unauthorized
          return false
        end

        true
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
