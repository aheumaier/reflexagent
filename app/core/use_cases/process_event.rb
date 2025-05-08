module UseCases
  class ProcessEvent
    def initialize(ingestion_port:, storage_port:, queue_port:, team_repository_port: nil, logger_port: nil)
      @ingestion_port = ingestion_port
      @storage_port = storage_port
      @queue_port = queue_port
      @team_repository_port = team_repository_port
      @logger_port = logger_port || Rails.logger
    end

    # Process a raw webhook payload
    # @param raw_payload [String] The raw JSON webhook payload
    # @param source [String] The source of the webhook (github, jira, etc.)
    # @return [Domain::Event] The processed domain event
    def call(raw_payload, source:)
      @logger_port.debug { "ProcessEvent.call starting for #{source} event" }

      # Parse the raw payload into a domain event
      begin
        event = @ingestion_port.receive_event(raw_payload, source: source)
        @logger_port.debug { "Event parsed: #{event.id} (#{event.name})" }
      rescue StandardError => e
        @logger_port.error("Error parsing event: #{e.message}")
        raise EventParsingError, "Failed to parse event: #{e.message}"
      end

      # Store the event in the repository
      begin
        stored_event = @storage_port.save_event(event)
        event = stored_event
        @logger_port.debug { "Event saved: #{event.id}" }
      rescue StandardError => e
        @logger_port.error("Error saving event: #{e.message}")
        raise EventStorageError, "Failed to save event: #{e.message}"
      end

      # Handle repository creation/update for GitHub repository-related events
      process_repository_from_event(event) if repository_event?(event)

      # Enqueue for async metric calculation
      begin
        @queue_port.enqueue_metric_calculation(event)
        @logger_port.debug { "Event enqueued for metric calculation: #{event.id}" }
      rescue StandardError => e
        @logger_port.error("Error enqueuing event: #{e.message}")
        # We don't want to fail the whole process if enqueueing fails
        # The event is already stored, so it can be recovered later
        @logger_port.error("Continuing despite enqueueing error")
      end

      # Return the processed event
      event
    end

    private

    # Check if event is related to GitHub repositories
    def repository_event?(event)
      return false unless event.name.start_with?("github.")

      # Extract the main event type
      _, event_type, = event.name.split(".")

      # Only process specific GitHub repository-related events
      ["push", "create", "repository"].include?(event_type) && @team_repository_port.present?
    end

    # Extract repository info and register/update repository
    def process_repository_from_event(event)
      # Extract repository info from event payload
      repo_info = extract_repository_info(event)
      return unless repo_info[:name].present?

      # Check if repository already exists
      existing_repo = @team_repository_port.find_repository_by_name(repo_info[:name])

      # Determine team ID to use
      team_id = if existing_repo&.team_id.present?
                  # If repository exists with a team, use that team
                  existing_repo.team_id
                else
                  # Otherwise try to find or create a team
                  # Extract organization name from repository name
                  org_name = extract_org_from_repo(repo_info[:name])

                  if org_name.present?
                    # Find or create a team for this organization
                    team = find_or_create_team_for_org(org_name)
                    team&.id
                  end || begin
                    # If we couldn't find or create a team, use the default team
                    default_team = ::Team.first
                    default_team&.id || 1
                  end
                end

      # Create or update repository
      @logger_port.info { "Registering repository from event: #{repo_info[:name]}" }

      use_case = UseCases::RegisterRepository.new(
        team_repository_port: @team_repository_port,
        logger_port: @logger_port
      )

      # Call the use case with named parameters that match its interface
      use_case.call(
        name: repo_info[:name],
        url: repo_info[:url],
        provider: "github",
        team_id: team_id
      )
    end

    # Find or create a team for an organization
    # @param org_name [String] The organization name
    # @return [Domain::Team, nil] The team, or nil if creation failed
    def find_or_create_team_for_org(org_name)
      return nil if org_name.blank?

      begin
        find_or_create_team_use_case = UseCases::FindOrCreateTeam.new(
          team_repository_port: @team_repository_port,
          logger_port: @logger_port
        )

        find_or_create_team_use_case.call(
          name: org_name,
          description: "Auto-created from GitHub organization '#{org_name}'"
        )
      rescue StandardError => e
        @logger_port.error { "Error creating team for org '#{org_name}': #{e.message}" }
        nil
      end
    end

    # Extract organization name from repository name
    # @param repo_name [String] The repository name (e.g., "org/repo")
    # @return [String, nil] The organization name, or nil if not found
    def extract_org_from_repo(repo_name)
      return nil unless repo_name.present?

      parts = repo_name.split("/")
      parts.size >= 2 ? parts.first : nil
    end

    # Extract repository information from an event
    # @param event [Domain::Event] The event to extract from
    # @return [Hash] Repository information
    def extract_repository_info(event)
      repo_info = { name: nil, url: nil }

      if event.name.start_with?("github.")
        repo_data = event.data[:repository] || {}
        repo_info[:name] = repo_data[:full_name]
        repo_info[:url] = repo_data[:html_url]
      end

      repo_info
    end

    # Custom error classes for clearer exception handling
    class EventParsingError < StandardError; end
    class EventStorageError < StandardError; end
  end
end
