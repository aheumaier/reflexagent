module Api
  module V1
    class GithubWebhookController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :verify_github_signature

      include Ports::IngestionPort

      # Handle all GitHub webhook events
      def create
        # Extract the event type from headers
        event_type = request.headers["X-GitHub-Event"]

        # Parse the payload
        payload = JSON.parse(request.body.read)

        # Create a domain event based on the GitHub event type
        event = build_domain_event(event_type, payload)

        # Process the event using the core use case
        use_case = UseCaseFactory.create_process_event
        processed_event = use_case.call(event)

        # Return a success response
        render json: {
          status: "processed",
          id: processed_event.id,
          event_type: event_type
        }, status: :created
      rescue JSON::ParserError => e
        Rails.logger.error("Invalid JSON in GitHub webhook: #{e.message}")
        render json: { error: "Invalid JSON payload" }, status: :bad_request
      rescue StandardError => e
        Rails.logger.error("Error processing GitHub webhook: #{e.message}")
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # Implementation of IngestionPort#receive_event
      def receive_event(payload)
        event_type = payload[:event_type]
        event_data = payload[:data]

        # Create a domain event
        Core::Domain::Event.new(
          name: "github.#{event_type}",
          source: "github",
          data: event_data,
          timestamp: Time.current
        )
      end

      # Implementation of IngestionPort#validate_webhook_signature
      def validate_webhook_signature(payload, signature)
        verify_github_signature
      end

      private

      # Verify the GitHub webhook signature
      def verify_github_signature
        # Get the raw payload
        payload_body = request.body.read
        request.body.rewind

        # Get the signature header
        signature_header = request.headers["X-Hub-Signature-256"]

        unless signature_header.present?
          Rails.logger.warn("Missing X-Hub-Signature-256 header in GitHub webhook")
          render json: { error: "Missing signature header" }, status: :unauthorized
          return false
        end

        # Calculate expected signature
        webhook_secret = Rails.application.credentials.dig(:github, :webhook_secret)
        unless webhook_secret.present?
          Rails.logger.error("GitHub webhook secret not configured")
          render json: { error: "Webhook secret not configured" }, status: :internal_server_error
          return false
        end

        # Calculate the expected signature
        expected_signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, payload_body)}"

        # Use constant-time comparison to prevent timing attacks
        unless ActiveSupport::SecurityUtils.secure_compare(expected_signature, signature_header)
          Rails.logger.warn("Invalid GitHub webhook signature")
          render json: { error: "Invalid signature" }, status: :unauthorized
          return false
        end

        true
      end

      # Build a Domain Event from GitHub webhook data
      def build_domain_event(event_type, payload)
        # Build event data based on the event type
        case event_type
        when "push"
          build_push_event(payload)
        when "pull_request"
          build_pull_request_event(payload)
        when "pull_request_review"
          build_pull_request_review_event(payload)
        else
          # Generic handler for other event types
          build_generic_event(event_type, payload)
        end
      end

      # Build a push event (commit)
      def build_push_event(payload)
        # Extract repository info
        repository = payload["repository"]["full_name"]
        ref = payload["ref"]
        branch = ref.gsub("refs/heads/", "")

        # For push events, create an event for the push itself
        # Commits will be in the payload data
        receive_event(
          event_type: "push",
          data: {
            repository: repository,
            ref: ref,
            branch: branch,
            commits: payload["commits"],
            pusher: payload["pusher"],
            sender: payload["sender"]
          }
        )
      end

      # Build a pull request event
      def build_pull_request_event(payload)
        # Extract PR info
        action = payload["action"]
        pr = payload["pull_request"]
        repository = payload["repository"]["full_name"]

        receive_event(
          event_type: "pull_request",
          data: {
            repository: repository,
            action: action,
            number: pr["number"],
            title: pr["title"],
            user: pr["user"],
            base: {
              ref: pr["base"]["ref"],
              sha: pr["base"]["sha"]
            },
            head: {
              ref: pr["head"]["ref"],
              sha: pr["head"]["sha"]
            },
            created_at: pr["created_at"],
            updated_at: pr["updated_at"],
            merged: pr["merged"],
            merged_at: pr["merged_at"],
            sender: payload["sender"]
          }
        )
      end

      # Build a pull request review event
      def build_pull_request_review_event(payload)
        action = payload["action"]
        review = payload["review"]
        pr = payload["pull_request"]
        repository = payload["repository"]["full_name"]

        receive_event(
          event_type: "pull_request_review",
          data: {
            repository: repository,
            action: action,
            pr_number: pr["number"],
            review_id: review["id"],
            review_state: review["state"],
            reviewer: review["user"],
            submitted_at: review["submitted_at"],
            pr_title: pr["title"],
            sender: payload["sender"]
          }
        )
      end

      # Handle any other type of event
      def build_generic_event(event_type, payload)
        receive_event(
          event_type: event_type,
          data: payload
        )
      end
    end
  end
end
