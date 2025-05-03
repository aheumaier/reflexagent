# frozen_string_literal: true

class RawEventJob
  include Sidekiq::Job

  # Set queue name
  sidekiq_options queue: "raw_events", retry: 3

  # Process a single raw event
  # @param payload_wrapper [Hash] The raw event payload wrapper containing the event data
  def perform(payload_wrapper)
    # Convert string keys to symbols (Sidekiq serializes to JSON with string keys)
    payload_wrapper = payload_wrapper.transform_keys(&:to_sym) if payload_wrapper.keys.first.is_a?(String)

    # Log the raw event for debugging
    Rails.logger.debug { "Processing raw event: #{payload_wrapper[:id]}" }

    # If this is a GitHub event, check for or infer the event type
    if payload_wrapper[:source] == "github"
      # For GitHub events, we should try to determine the event type if not provided
      event_type = infer_github_event_type(payload_wrapper[:payload])
      if event_type
        Rails.logger.info("Inferred GitHub event_type: #{event_type}")
        # Store in thread local for the web adapter to access
        Thread.current[:http_headers] = { "X-GitHub-Event" => event_type }
      end
    end

    # Get the process_event use case to handle this event
    use_case = UseCaseFactory.create_process_event

    # Call the use case with the raw payload and source
    use_case.call(payload_wrapper[:payload], source: payload_wrapper[:source])

    # Log success
    Rails.logger.info("Processed raw event (id: #{payload_wrapper[:id]})")
  rescue StandardError => e
    # Log errors
    Rails.logger.error("Error processing raw event #{payload_wrapper[:id]}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    # Sidekiq will automatically retry based on our sidekiq_options
    # After max retries, it will go to the Dead Job Queue
    raise
  ensure
    # Always clear thread-local storage
    Thread.current[:http_headers] = nil
  end

  private

  # Try to infer the GitHub event type from the payload
  # This helps when X-GitHub-Event header is not available
  def infer_github_event_type(payload)
    payload = JSON.parse(payload, symbolize_names: true) if payload.is_a?(String)

    # Look for patterns in the payload to determine event type
    if payload[:ref_type] && payload[:ref] && !payload.key?(:commits)
      return "create"  # Branch or tag creation
    elsif payload[:ref] && payload[:commits]
      return "push"    # Push event
    elsif payload[:pull_request]
      return "pull_request"
    elsif payload[:issue] && !payload[:pull_request]
      return "issues"
    elsif payload[:check_run]
      return "check_run"
    elsif payload[:check_suite]
      return "check_suite"
    elsif payload[:workflow_run]
      return "workflow_run"
    elsif payload[:workflow_job]
      return "workflow_job"
    elsif payload[:deployment] && !payload[:deployment_status]
      return "deployment"
    elsif payload[:deployment_status]
      return "deployment_status"
    end

    nil # Couldn't determine
  end
end
