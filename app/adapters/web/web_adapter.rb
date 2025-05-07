# frozen_string_literal: true

require_relative "../../ports/ingestion_port"
require_relative "../../core/domain/event_factory"

module Web
  class WebAdapter
    include IngestionPort

    # Implements the IngestionPort interface
    # Parses the raw payload and creates a Domain Event
    # @param raw_payload [String] The raw JSON webhook payload
    # @param source [String] The source system (github, jira, gitlab, etc.)
    # @return [Domain::Event] A domain event
    def receive_event(raw_payload, source:)
      # Parse the JSON payload
      parsed_payload = JSON.parse(raw_payload, symbolize_names: true)

      # Process the event based on source

      # Create and return a domain event based on the source
      case source
      when "github"
        handle_github_event(parsed_payload)
      when "jira"
        handle_jira_event(parsed_payload)
      when "gitlab"
        handle_gitlab_event(parsed_payload)
      when "bitbucket"
        handle_bitbucket_event(parsed_payload)
      else
        handle_generic_event(parsed_payload, source)
      end
    rescue JSON::ParserError => e
      Rails.logger.error("Invalid JSON payload: #{e.message}")
      raise InvalidPayloadError, "Invalid JSON payload"
    end

    # Validate webhook signatures based on the source
    # @param payload [String] The raw webhook payload
    # @param signature [String] The signature header
    # @return [Boolean] Whether the signature is valid
    def validate_webhook_signature(payload, signature)
      # Implementation would depend on each source's signature algorithm
      # This would be delegated to specific signature validators
      true # Placeholder implementation
    end

    private

    # Handle GitHub specific event mapping
    def handle_github_event(payload)
      # Process the GitHub event

      # Determine event type from payload
      # GitHub webhooks can have various formats depending on the event type
      event_type = determine_github_event_type(payload)
      repository = payload.dig(:repository, :full_name) || "unknown"

      # Create a domain event using the EventFactory
      begin
        Domain::EventFactory.create(
          name: "github.#{event_type}",
          source: "github",
          data: payload,
          timestamp: Time.current
        )
      rescue StandardError => e
        Rails.logger.error("Error creating event: #{e.message}")
        raise e
      end
    end

    # Helper method to determine GitHub event type from payload
    def determine_github_event_type(payload)
      # The payload may have string keys instead of symbols when coming from demo_events.rb
      # We'll support both by checking for string keys as well
      ref_type = payload[:ref_type] || payload["ref_type"]
      ref = payload[:ref] || payload["ref"]
      has_commits = payload.key?(:commits) || payload.key?("commits")
      is_deleted = payload[:deleted] || payload["deleted"]

      # Check for branch/tag deletion events (delete event)
      # This check needs to come before the create event check
      return "delete" if ref_type && ref && is_deleted

      # SPECIAL FOR CREATE EVENT: Use the fact that no action field indicates it's a "create" event
      # This is an important check for our branch creation events
      return "create" if ref_type && ref && !has_commits && !payload.key?(:action) && !payload.key?("action")

      # Check for branch/tag creation events (create event)
      return "create" if ref_type && ref && !has_commits

      # Check for push events
      return "push" if ref && has_commits

      # Remaining checks use the same pattern...

      action = payload[:action] || payload["action"]
      deployment = payload[:deployment] || payload["deployment"]
      deployment_status = payload[:deployment_status] || payload["deployment_status"]
      workflow_run = payload[:workflow_run] || payload["workflow_run"]
      workflow_job = payload[:workflow_job] || payload["workflow_job"]
      issue = payload[:issue] || payload["issue"]
      pull_request = payload[:pull_request] || payload["pull_request"]
      comment = payload[:comment] || payload["comment"]
      review = payload[:review] || payload["review"]
      check_run = payload[:check_run] || payload["check_run"]
      check_suite = payload[:check_suite] || payload["check_suite"]
      repository = payload[:repository] || payload["repository"]

      # Check for deployment events
      return "deployment.#{action}" if deployment && action

      # Check for deployment status events
      return "deployment_status.#{action}" if deployment_status && action

      # Check for workflow run events
      return "workflow_run.#{action}" if workflow_run && action

      # Check for workflow job events
      return "workflow_job.#{action}" if workflow_job && action

      # Check for issue events
      return "issues.#{action}" if action && issue && !comment

      # Check for pull request events
      return "pull_request.#{action}" if action && pull_request && !comment && !review

      # Check for issue comment events
      return "issue_comment.#{action}" if action && comment && issue

      # Check for PR comment events
      return "pull_request_review_comment.#{action}" if action && comment && pull_request

      # Check for pull request review events
      return "pull_request_review.#{action}" if action && review && pull_request

      # Check for check run events
      return "check_run.#{action}" if action && check_run

      # Check for check suite events
      return "check_suite.#{action}" if action && check_suite

      # Check for repository events
      return "repository.#{action}" if action && repository && !issue && !pull_request

      # Generic fallback
      # If we have an action but couldn't categorize the event, use it
      return "#{action}" if action

      # Last resort fallback
      "unknown"
    end

    # Handle Jira specific event mapping
    def handle_jira_event(payload)
      event_type = payload[:webhookEvent] || "unknown"
      issue_key = payload.dig(:issue, :key) || "unknown"

      Domain::EventFactory.create(
        name: "jira.#{event_type}",
        source: "jira",
        data: payload,
        timestamp: Time.current
      )
    end

    # Handle GitLab specific event mapping
    def handle_gitlab_event(payload)
      event_type = payload[:object_kind] || "unknown"
      project = payload.dig(:project, :path_with_namespace) || "unknown"

      Domain::EventFactory.create(
        name: "gitlab.#{event_type}",
        source: "gitlab",
        data: payload,
        timestamp: Time.current
      )
    end

    # Handle Bitbucket specific event mapping
    def handle_bitbucket_event(payload)
      event_type = payload[:event_key] || "unknown"
      repository = payload.dig(:repository, :full_name) || "unknown"

      Domain::EventFactory.create(
        name: "bitbucket.#{event_type}",
        source: "bitbucket",
        data: payload,
        timestamp: Time.current
      )
    end

    # Generic handler for other sources
    def handle_generic_event(payload, source)
      # Extract a reasonable event name or use a default
      event_type = payload[:type] || payload[:event] || payload[:action] || "event"

      Domain::EventFactory.create(
        name: "#{source}.#{event_type}",
        source: source,
        data: payload,
        timestamp: Time.current
      )
    end

    class InvalidPayloadError < StandardError; end
  end
end
