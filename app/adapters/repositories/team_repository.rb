# frozen_string_literal: true

require_relative "../../ports/storage_port"
require_relative "../../core/domain/team"
require_relative "../../core/domain/code_repository"

module Repositories
  # Database implementation of team and repository storage
  class TeamRepository
    include StoragePort

    def initialize(logger_port: nil)
      @logger_port = logger_port || Rails.logger
    end

    # Team methods

    def find_team(id)
      return nil unless id

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

    def find_team_by_slug(slug)
      return nil unless slug

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

    def find_team_by_name(name)
      return nil unless name

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

    def save_team(team)
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
    rescue ActiveRecord::RecordInvalid => e
      @logger_port.error("Failed to save team: #{e.message}")
      raise "Failed to save team: #{e.message}"
    end

    def list_teams
      ::Team.all.map do |team|
        Domain::Team.new(
          id: team.id,
          name: team.name,
          slug: team.slug,
          description: team.description
        )
      end
    end

    # Repository methods

    def find_repository(id)
      return nil unless id

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

    def find_repository_by_name(name)
      return nil unless name

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

    def save_repository(repository)
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
    rescue ActiveRecord::RecordInvalid => e
      @logger_port.error("Failed to save repository: #{e.message}")
      raise "Failed to save repository: #{e.message}"
    end

    def list_repositories(team_id: nil, limit: nil)
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

    # Find repositories for a specific team with pagination
    # @param team_id [Integer] The team ID to filter by
    # @param limit [Integer] Maximum number of repositories to return
    # @param offset [Integer] Offset for pagination
    # @return [Array<Domain::CodeRepository>] Repositories for the team
    def list_repositories_for_team(team_id, limit: nil, offset: 0)
      # Make sure we have a valid team ID
      return [] if team_id.nil?

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

    def delete_repository(id)
      return false unless id

      repo = ::CodeRepository.find_by(id: id)
      return false unless repo

      repo.destroy
      true
    rescue StandardError => e
      @logger_port.error("Failed to delete repository: #{e.message}")
      false
    end
  end
end
