# frozen_string_literal: true

module Domain
  # Team is a first-class domain entity that represents a team that owns code_repositories
  class Team
    attr_reader :id, :name, :slug, :description, :created_at, :updated_at

    def initialize(name:, id: nil, slug: nil, description: nil, created_at: Time.now, updated_at: Time.now)
      @id = id
      @name = name
      @slug = slug || name.to_s.parameterize
      @description = description
      @created_at = created_at
      @updated_at = updated_at
      validate!
    end

    # Validation methods
    def valid?
      name.present? && slug.present?
    end

    def validate!
      raise ArgumentError, "Name cannot be empty" if name.nil? || name.empty?
      raise ArgumentError, "Slug cannot be empty" if slug.nil? || slug.empty?
    end

    # Equality methods for testing
    def ==(other)
      return false unless other.is_a?(Team)

      id == other.id &&
        name == other.name &&
        slug == other.slug &&
        description == other.description
    end

    alias eql? ==

    def hash
      [id, name, slug, description].hash
    end

    # Serialization for transport/storage
    def to_h
      {
        id: id,
        name: name,
        slug: slug,
        description: description,
        created_at: created_at,
        updated_at: updated_at
      }
    end

    # Create a new instance with an updated ID
    def with_id(new_id)
      self.class.new(
        id: new_id,
        name: name,
        slug: slug,
        description: description,
        created_at: created_at,
        updated_at: updated_at
      )
    end
  end
end
