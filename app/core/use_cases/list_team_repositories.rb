# frozen_string_literal: true

module UseCases
  # ListTeamRepositories retrieves all repositories associated with a specific team
  class ListTeamRepositories
    def initialize(team_repository_port:, cache_port: nil, logger_port: nil)
      @team_repository_port = team_repository_port
      @cache_port = cache_port
      @logger_port = logger_port || Rails.logger
    end

    # @param team_id [Integer, String] The ID of the team
    # @param team_slug [String] Alternative to team_id - the slug of the team
    # @param limit [Integer] Maximum number of repositories to return
    # @param offset [Integer] Offset for pagination
    # @return [Array<Domain::CodeRepository>] List of repositories owned by the team
    def call(team_id: nil, team_slug: nil, limit: 100, offset: 0)
      # Must provide either team_id or team_slug
      raise ArgumentError, "Either team_id or team_slug must be provided" if team_id.nil? && team_slug.nil?

      # Find team by slug if team_id not provided
      if team_id.nil? && team_slug.present?
        team = @team_repository_port.find_team_by_slug(team_slug)
        raise ArgumentError, "Team with slug '#{team_slug}' not found" unless team

        team_id = team.id
      end

      # Try to get from cache first
      if @cache_port && (cached_result = from_cache(team_id, limit, offset))
        @logger_port.debug { "Retrieved team repositories from cache for team: #{team_id}" }
        return cached_result
      end

      # If not in cache, query repositories
      repositories = @team_repository_port.list_repositories_for_team(
        team_id,
        limit: limit,
        offset: offset
      )

      # Cache the result if caching is enabled
      cache_result(repositories, team_id, limit, offset) if @cache_port

      repositories
    end

    private

    # Caching methods

    def cache_key(team_id, limit, offset)
      "team_repositories:team_#{team_id}:limit_#{limit}:offset_#{offset}"
    end

    def from_cache(team_id, limit, offset)
      key = cache_key(team_id, limit, offset)
      cached = @cache_port.read(key)
      return nil unless cached

      # Parse and recreate domain entities
      if cached.is_a?(String)
        begin
          repo_data = JSON.parse(cached, symbolize_names: true)
          repo_data.map do |repo|
            Domain::CodeRepository.new(
              id: repo[:id],
              name: repo[:name],
              url: repo[:url],
              provider: repo[:provider],
              team_id: repo[:team_id],
              created_at: Time.parse(repo[:created_at]),
              updated_at: Time.parse(repo[:updated_at])
            )
          end
        rescue JSON::ParserError, TypeError => e
          @logger_port.error { "Failed to parse cache data for team repositories: #{e.message}" }
          nil
        end
      else
        cached # Already in the right format
      end
    end

    def cache_result(repositories, team_id, limit, offset)
      key = cache_key(team_id, limit, offset)

      # Convert to serializable format
      serialized = repositories.map(&:to_h)

      # Cache for 10 minutes - frequently changing association
      @cache_port.write(key, serialized.to_json, expires_in: 10.minutes)
      @logger_port.debug { "Cached #{repositories.size} repositories for team #{team_id}" }
    rescue StandardError => e
      @logger_port.error { "Failed to cache team repositories: #{e.message}" }
    end
  end
end
