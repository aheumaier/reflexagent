# frozen_string_literal: true

module UseCases
  # RegisterRepository creates or updates a repository and optionally associates it with a team
  class RegisterRepository
    def initialize(team_repository_port:, logger_port: nil)
      @team_repository_port = team_repository_port
      @logger_port = logger_port || Rails.logger
    end

    # @param name [String] Repository name (e.g., "org/repo")
    # @param url [String] Repository URL (optional)
    # @param provider [String] Provider name (default: "github")
    # @param team_id [Integer, String] Team ID to associate with (optional)
    # @param team_slug [String] Alternative to team_id - the slug of the team (optional)
    # @return [Domain::CodeRepository] The registered repository
    def call(name:, url: nil, provider: "github", team_id: nil, team_slug: nil)
      # Find team by slug if team_id not provided but team_slug is
      if team_id.nil? && team_slug.present?
        team = @team_repository_port.find_team_by_slug(team_slug)
        raise ArgumentError, "Team with slug '#{team_slug}' not found" unless team

        team_id = team.id
      end

      # Check if repository already exists
      existing_repo = @team_repository_port.find_repository_by_name(name)

      if existing_repo
        @logger_port.info { "Updating existing repository: #{name}" }

        # Update existing repository
        updated_repo = Domain::CodeRepository.new(
          id: existing_repo.id,
          name: existing_repo.name,
          url: url || existing_repo.url,
          provider: provider || existing_repo.provider,
          team_id: team_id || existing_repo.team_id
        )

        # Save the updated repository
        @team_repository_port.save_repository(updated_repo)
      else
        @logger_port.info { "Creating new repository: #{name}" }

        # Create new repository
        new_repo = Domain::CodeRepository.new(
          name: name,
          url: url,
          provider: provider,
          team_id: team_id
        )

        # Save the new repository
        @team_repository_port.save_repository(new_repo)
      end
    end
  end
end
