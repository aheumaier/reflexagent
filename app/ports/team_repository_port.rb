# frozen_string_literal: true

# TeamRepositoryPort defines the interface for working with teams and code repositories
module TeamRepositoryPort
  # Team operations

  # Save a team to storage
  # @param team [Domain::Team] The team to save
  # @return [Domain::Team] The saved team with ID
  def save_team(team)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Find a team by ID
  # @param id [Integer, String] The ID of the team to find
  # @return [Domain::Team, nil] The team if found, nil otherwise
  def find_team(id)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Find a team by slug
  # @param slug [String] The slug of the team to find
  # @return [Domain::Team, nil] The team if found, nil otherwise
  def find_team_by_slug(slug)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # List all teams
  # @param limit [Integer] Maximum number of teams to return
  # @param offset [Integer] Offset for pagination
  # @return [Array<Domain::Team>] List of teams
  def list_teams(limit: 100, offset: 0)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Repository operations

  # Save a code repository to storage
  # @param repository [Domain::CodeRepository] The repository to save
  # @return [Domain::CodeRepository] The saved repository with ID
  def save_repository(repository)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Find a repository by ID
  # @param id [Integer, String] The ID of the repository to find
  # @return [Domain::CodeRepository, nil] The repository if found, nil otherwise
  def find_repository(id)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Find a repository by name
  # @param name [String] The name of the repository to find (e.g., "org/repo")
  # @return [Domain::CodeRepository, nil] The repository if found, nil otherwise
  def find_repository_by_name(name)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # List all repositories
  # @param limit [Integer] Maximum number of repositories to return
  # @param offset [Integer] Offset for pagination
  # @return [Array<Domain::CodeRepository>] List of repositories
  def list_repositories(limit: 100, offset: 0)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Team-Repository relationship operations

  # List repositories for a team
  # @param team_id [Integer, String] The ID of the team
  # @param limit [Integer] Maximum number of repositories to return
  # @param offset [Integer] Offset for pagination
  # @return [Array<Domain::CodeRepository>] List of repositories owned by the team
  def list_repositories_for_team(team_id, limit: 100, offset: 0)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Find the team that owns a repository
  # @param repository_id [Integer, String] The ID of the repository
  # @return [Domain::Team, nil] The owning team if found, nil otherwise
  def find_team_for_repository(repository_id)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Associate a repository with a team
  # @param repository_id [Integer, String] The repository ID
  # @param team_id [Integer, String] The team ID
  # @return [Boolean] Success status
  def associate_repository_with_team(repository_id, team_id)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end
end
