# frozen_string_literal: true

module UseCases
  # FindOrCreateTeam finds a team by name or creates a new one if it doesn't exist
  class FindOrCreateTeam
    def initialize(team_repository_port:, logger_port: nil)
      @team_repository_port = team_repository_port
      @logger_port = logger_port || Rails.logger
    end

    # Find or create a team by name
    # @param name [String] The name of the team to find or create
    # @param description [String, nil] Description for the team (if created)
    # @return [Domain::Team] The existing or new team
    def call(name:, description: nil)
      # Normalize name and generate slug
      normalized_name = name.to_s.strip.presence || "Unknown"
      slug = normalized_name.parameterize

      # First try to find by slug
      existing_team = @team_repository_port.find_team_by_slug(slug)
      if existing_team
        @logger_port.debug { "Found existing team by slug: #{slug}" }
        return existing_team
      end

      # Create a new team
      @logger_port.info { "Creating new team: #{normalized_name} (#{slug})" }

      new_team = Domain::Team.new(
        name: normalized_name,
        slug: slug,
        description: description || "Auto-created from organization name"
      )

      # Save the new team
      @team_repository_port.save_team(new_team)
    end
  end
end
