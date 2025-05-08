# frozen_string_literal: true

module Domain
  # CodeRepository is a first-class domain entity that represents a source code repository
  # that is owned by a Team.
  class CodeRepository
    attr_reader :id, :name, :url, :provider, :team_id, :created_at, :updated_at

    def initialize(name:, id: nil, url: nil, provider: "github", team_id: nil, created_at: Time.now,
                   updated_at: Time.now)
      @id = id
      @name = name
      @url = url
      @provider = provider
      @team_id = team_id
      @created_at = created_at
      @updated_at = updated_at
      validate!
    end

    # Validation methods
    def valid?
      name.present? && provider.present?
    end

    def validate!
      raise ArgumentError, "Name cannot be empty" if name.nil? || name.empty?
      raise ArgumentError, "Provider cannot be empty" if provider.nil? || provider.empty?
    end

    # Equality methods for testing
    def ==(other)
      return false unless other.is_a?(CodeRepository)

      id == other.id &&
        name == other.name &&
        url == other.url &&
        provider == other.provider &&
        team_id == other.team_id
    end

    alias eql? ==

    def hash
      [id, name, url, provider, team_id].hash
    end

    # Serialization for transport/storage
    def to_h
      {
        id: id,
        name: name,
        url: url,
        provider: provider,
        team_id: team_id,
        created_at: created_at,
        updated_at: updated_at
      }
    end

    # Create a new instance with an updated ID
    def with_id(new_id)
      self.class.new(
        id: new_id,
        name: name,
        url: url,
        provider: provider,
        team_id: team_id,
        created_at: created_at,
        updated_at: updated_at
      )
    end

    # Associate this repository with a team
    def with_team(team_id)
      self.class.new(
        id: id,
        name: name,
        url: url,
        provider: provider,
        team_id: team_id,
        created_at: created_at,
        updated_at: updated_at
      )
    end

    # Extract the owner/org and repo name from a full repository name (e.g., "org/repo")
    def self.parse_full_name(full_name)
      parts = full_name.to_s.split("/")
      if parts.size >= 2
        { owner: parts[0], repo: parts[1..-1].join("/") }
      else
        { owner: nil, repo: full_name }
      end
    end

    # Format the full repository name (e.g., "org/repo")
    def full_name
      owner, repo = name.to_s.split("/", 2)
      repo ? "#{owner}/#{repo}" : name
    end
  end
end
