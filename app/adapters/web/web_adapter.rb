# frozen_string_literal: true

require_relative "../../ports/ingestion_port"
module Web
  class WebAdapter
    include IngestionPort

    # Implements the IngestionPort interface
    # Parses the raw payload and creates a Domain Event
    # @param raw_payload [String] The raw JSON webhook payload
    # @param source [String] The source system (github, jira, gitlab, etc.)
    # @return [Core::Domain::Event] A domain event
    def receive_event(raw_payload, source:)
      # Parse the JSON payload
      parsed_payload = JSON.parse(raw_payload, symbolize_names: true)

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
      # Determine event type from payload
      # GitHub webhooks can have various formats depending on the event type
      event_type = determine_github_event_type(payload)
      repository = payload.dig(:repository, :full_name) || "unknown"

      Rails.logger.debug { "Creating GitHub event: #{event_type} for repo: #{repository}" }

      # Create a domain event using the loaded Core::Domain::Event class
      # Log before creating to help debug any issues
      begin
        event = Core::Domain::Event.new(
          name: "github.#{event_type}",
          source: "github",
          data: payload,
          timestamp: Time.current
        )
        Rails.logger.debug { "Successfully created event: #{event.id}" }
        event
      rescue StandardError => e
        Rails.logger.error("Error creating event: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        raise e
      end
    end

    # Helper method to determine GitHub event type from payload
    def determine_github_event_type(payload)
      if payload[:ref] && payload[:commits]
        # This is a push event
        "push"
      elsif payload[:action] && payload[:issue]
        # This is an issue event
        "issue.#{payload[:action]}"
      elsif payload[:action] && payload[:pull_request]
        # This is a pull request event
        "pull_request.#{payload[:action]}"
      elsif payload[:action] && payload[:comment] && payload[:issue]
        # This is an issue comment event
        "issue_comment.#{payload[:action]}"
      elsif payload[:action] && payload[:comment] && payload[:pull_request]
        # This is a PR comment event
        "pull_request_review_comment.#{payload[:action]}"
      else
        # Generic fallback
        payload[:action] || "unknown"
      end
    end

    # Handle Jira specific event mapping
    def handle_jira_event(payload)
      event_type = payload[:webhookEvent] || "unknown"
      issue_key = payload.dig(:issue, :key) || "unknown"

      Core::Domain::Event.new(
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

      Core::Domain::Event.new(
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

      Core::Domain::Event.new(
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

      Core::Domain::Event.new(
        name: "#{source}.#{event_type}",
        source: source,
        data: payload,
        timestamp: Time.current
      )
    end

    class InvalidPayloadError < StandardError; end
  end
end
