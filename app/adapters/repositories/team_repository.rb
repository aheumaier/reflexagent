# frozen_string_literal: true

require_relative "../../ports/storage_port"
require_relative "../../core/domain/team"
require_relative "../../core/domain/code_repository"
require_relative "concerns/error_handler"

module Repositories
  # Database implementation of team and repository storage
  class TeamRepository
    include StoragePort
    include Repositories::Concerns::ErrorHandler

    def initialize(logger_port: nil)
      @logger_port = logger_port || Rails.logger
    end

    # Team methods

    def find_team(id)
      return nil unless id

      context = { id: id }

      handle_database_error("find_team", context) do
        team = ::Team.find_by(id: id)
        return nil unless team

        # Convert to domain team
        Domain::Team.new(
          id: team.id,
          name: team.name,
          slug: team.slug,
          description: team.description
        )
      end
    end

    def find_team_by_slug(slug)
      return nil unless slug

      context = { slug: slug }

      handle_database_error("find_team_by_slug", context) do
        team = ::Team.find_by(slug: slug)
        return nil unless team

        # Convert to domain team
        Domain::Team.new(
          id: team.id,
          name: team.name,
          slug: team.slug,
          description: team.description
        )
      end
    end

    def find_team_by_name(name)
      return nil unless name

      context = { name: name }

      handle_database_error("find_team_by_name", context) do
        team = ::Team.find_by(name: name)
        return nil unless team

        # Convert to domain team
        Domain::Team.new(
          id: team.id,
          name: team.name,
          slug: team.slug,
          description: team.description
        )
      end
    end

    def save_team(team)
      # Validate input
      raise ArgumentError, "Team cannot be nil" unless team
      raise ArgumentError, "Team name cannot be blank" if team.name.nil? || team.name.empty?

      context = {
        id: team.id,
        name: team.name,
        slug: team.slug
      }

      handle_database_error("save_team", context) do
        # Try to find existing team by id
        existing_team = team.id ? ::Team.find_by(id: team.id) : nil

        if existing_team
          # Update existing team
          existing_team.update!(
            name: team.name,
            slug: team.slug,
            description: team.description
          )

          # Return the domain team with the database ID
          Domain::Team.new(
            id: existing_team.id,
            name: existing_team.name,
            slug: existing_team.slug,
            description: existing_team.description
          )
        else
          # Create new team
          new_team = ::Team.create!(
            name: team.name,
            slug: team.slug,
            description: team.description
          )

          # Return the domain team with the database ID
          Domain::Team.new(
            id: new_team.id,
            name: new_team.name,
            slug: new_team.slug,
            description: new_team.description
          )
        end
      end
    end

    def list_teams
      context = {}

      handle_query_error("list_teams", context) do
        ::Team.all.map do |team|
          Domain::Team.new(
            id: team.id,
            name: team.name,
            slug: team.slug,
            description: team.description
          )
        end
      end
    end

    # Repository methods

    def find_repository(id)
      return nil unless id

      context = { id: id }

      handle_database_error("find_repository", context) do
        repo = ::CodeRepository.find_by(id: id)
        return nil unless repo

        # Convert to domain repository
        Domain::CodeRepository.new(
          id: repo.id,
          name: repo.name,
          url: repo.url,
          provider: repo.provider,
          team_id: repo.team_id
        )
      end
    end

    def find_repository_by_name(name)
      return nil unless name

      context = { name: name }

      handle_database_error("find_repository_by_name", context) do
        repo = ::CodeRepository.find_by(name: name)
        return nil unless repo

        # Convert to domain repository
        Domain::CodeRepository.new(
          id: repo.id,
          name: repo.name,
          url: repo.url,
          provider: repo.provider,
          team_id: repo.team_id
        )
      end
    end

    def save_repository(repository)
      # Validate input
      raise ArgumentError, "Repository cannot be nil" unless repository
      raise ArgumentError, "Repository name cannot be blank" if repository.name.nil? || repository.name.empty?

      context = {
        id: repository.id,
        name: repository.name,
        team_id: repository.team_id
      }

      handle_database_error("save_repository", context) do
        # Try to find existing repository by id or name
        existing_repo = nil
        existing_repo = ::CodeRepository.find_by(id: repository.id) if repository.id

        # If not found by ID, try by name
        existing_repo ||= ::CodeRepository.find_by(name: repository.name) if repository.name

        if existing_repo
          # Update existing repository
          existing_repo.update!(
            name: repository.name,
            url: repository.url,
            provider: repository.provider,
            team_id: repository.team_id
          )

          # Return the domain repository with the database ID
          Domain::CodeRepository.new(
            id: existing_repo.id,
            name: existing_repo.name,
            url: existing_repo.url,
            provider: existing_repo.provider,
            team_id: existing_repo.team_id
          )
        else
          # Create new repository
          new_repo = ::CodeRepository.create!(
            name: repository.name,
            url: repository.url,
            provider: repository.provider,
            team_id: repository.team_id
          )

          # Return the domain repository with the database ID
          Domain::CodeRepository.new(
            id: new_repo.id,
            name: new_repo.name,
            url: new_repo.url,
            provider: new_repo.provider,
            team_id: new_repo.team_id
          )
        end
      end
    end

    def list_repositories(team_id: nil, limit: nil)
      context = {
        team_id: team_id,
        limit: limit
      }

      handle_query_error("list_repositories", context) do
        query = ::CodeRepository.all
        query = query.where(team_id: team_id) if team_id
        query = query.limit(limit) if limit

        query.map do |repo|
          Domain::CodeRepository.new(
            id: repo.id,
            name: repo.name,
            url: repo.url,
            provider: repo.provider,
            team_id: repo.team_id
          )
        end
      end
    end

    # Find repositories for a specific team with pagination
    # @param team_id [Integer] The team ID to filter by
    # @param limit [Integer] Maximum number of repositories to return
    # @param offset [Integer] Offset for pagination
    # @return [Array<Domain::CodeRepository>] Repositories for the team
    def list_repositories_for_team(team_id, limit: nil, offset: 0)
      # Validate input
      raise ArgumentError, "Team ID cannot be nil" unless team_id

      context = {
        team_id: team_id,
        limit: limit,
        offset: offset
      }

      handle_query_error("list_repositories_for_team", context) do
        # Start with the base query
        query = ::CodeRepository.where(team_id: team_id)
        query = query.limit(limit) if limit
        query = query.offset(offset) if offset && offset > 0

        # Map to domain objects
        query.map do |repo|
          Domain::CodeRepository.new(
            id: repo.id,
            name: repo.name,
            url: repo.url,
            provider: repo.provider,
            team_id: repo.team_id
          )
        end
      end
    end

    def delete_repository(id)
      # Validate input
      raise ArgumentError, "Repository ID cannot be nil" unless id

      context = { id: id }

      handle_database_error("delete_repository", context) do
        repo = ::CodeRepository.find_by(id: id)
        return false unless repo

        repo.destroy
        true
      end
    end
  end
end
