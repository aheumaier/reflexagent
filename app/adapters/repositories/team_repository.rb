# frozen_string_literal: true

require_relative "../../ports/team_repository_port"

module Repositories
  # TeamRepository implements TeamRepositoryPort using ActiveRecord models
  class TeamRepository
    include TeamRepositoryPort

    # Team operations

    # Save a team to storage
    # @param team [Domain::Team] The team to save
    # @return [Domain::Team] The saved team with ID
    def save_team(team)
      # Check if the team already exists (update case)
      if team.id.present?
        # Find existing record
        ar_team = ::Team.find_by(id: team.id)
        return nil unless ar_team

        # Update the record
        ar_team.update!(
          name: team.name,
          slug: team.slug,
          description: team.description
        )
      else
        # Create a new record
        ar_team = ::Team.from_domain(team)
        ar_team.save!
      end

      # Return a fresh domain entity
      ar_team.to_domain
    end

    # Find a team by ID
    # @param id [Integer, String] The ID of the team to find
    # @return [Domain::Team, nil] The team if found, nil otherwise
    def find_team(id)
      team = ::Team.find_by(id: id)
      team&.to_domain
    end

    # Find a team by slug
    # @param slug [String] The slug of the team to find
    # @return [Domain::Team, nil] The team if found, nil otherwise
    def find_team_by_slug(slug)
      team = ::Team.find_by(slug: slug)
      team&.to_domain
    end

    # List all teams
    # @param limit [Integer] Maximum number of teams to return
    # @param offset [Integer] Offset for pagination
    # @return [Array<Domain::Team>] List of teams
    def list_teams(limit: 100, offset: 0)
      ::Team.order(:name)
            .limit(limit)
            .offset(offset)
            .map(&:to_domain)
    end

    # Repository operations

    # Save a code repository to storage
    # @param repository [Domain::CodeRepository] The repository to save
    # @return [Domain::CodeRepository] The saved repository with ID
    def save_repository(repository)
      # Check if the repository already exists (update case)
      if repository.id.present?
        # Find existing record
        ar_repo = ::CodeRepository.find_by(id: repository.id)
        return nil unless ar_repo

        # Update the record
        ar_repo.update!(
          name: repository.name,
          url: repository.url,
          provider: repository.provider,
          team_id: repository.team_id
        )
      else
        # Try to find an existing repository by name and provider
        ar_repo = ::CodeRepository.find_by(
          name: repository.name,
          provider: repository.provider
        )

        if ar_repo
          # Update existing repository
          ar_repo.update!(
            url: repository.url,
            team_id: repository.team_id
          )
        else
          # Create a new record
          ar_repo = ::CodeRepository.from_domain(repository)
          ar_repo.save!
        end
      end

      # Return a fresh domain entity
      ar_repo.to_domain
    end

    # Find a repository by ID
    # @param id [Integer, String] The ID of the repository to find
    # @return [Domain::CodeRepository, nil] The repository if found, nil otherwise
    def find_repository(id)
      repo = ::CodeRepository.find_by(id: id)
      repo&.to_domain
    end

    # Find a repository by name
    # @param name [String] The name of the repository to find (e.g., "org/repo")
    # @return [Domain::CodeRepository, nil] The repository if found, nil otherwise
    def find_repository_by_name(name)
      repo = ::CodeRepository.find_by(name: name)
      repo&.to_domain
    end

    # List all repositories
    # @param limit [Integer] Maximum number of repositories to return
    # @param offset [Integer] Offset for pagination
    # @return [Array<Domain::CodeRepository>] List of repositories
    def list_repositories(limit: 100, offset: 0)
      ::CodeRepository.order(:name)
                      .limit(limit)
                      .offset(offset)
                      .map(&:to_domain)
    end

    # Team-Repository relationship operations

    # List repositories for a team
    # @param team_id [Integer, String] The ID of the team
    # @param limit [Integer] Maximum number of repositories to return
    # @param offset [Integer] Offset for pagination
    # @return [Array<Domain::CodeRepository>] List of repositories owned by the team
    def list_repositories_for_team(team_id, limit: 100, offset: 0)
      ::CodeRepository.by_team(team_id)
                      .order(:name)
                      .limit(limit)
                      .offset(offset)
                      .map(&:to_domain)
    end

    # Find the team that owns a repository
    # @param repository_id [Integer, String] The ID of the repository
    # @return [Domain::Team, nil] The owning team if found, nil otherwise
    def find_team_for_repository(repository_id)
      repo = ::CodeRepository.find_by(id: repository_id)
      return nil unless repo&.team_id

      team = ::Team.find_by(id: repo.team_id)
      team&.to_domain
    end

    # Associate a repository with a team
    # @param repository_id [Integer, String] The repository ID
    # @param team_id [Integer, String] The team ID
    # @return [Boolean] Success status
    def associate_repository_with_team(repository_id, team_id)
      repo = ::CodeRepository.find_by(id: repository_id)
      return false unless repo

      # Verify team exists
      team = ::Team.find_by(id: team_id)
      return false unless team

      # Update the repository's team_id
      repo.update(team_id: team_id)
    end
  end
end
