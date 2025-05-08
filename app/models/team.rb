# frozen_string_literal: true

# Team ActiveRecord model that maps to the teams table
class Team < ApplicationRecord
  has_many :code_repositories, dependent: :nullify

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  # Convert to domain entity
  def to_domain
    Domain::Team.new(
      id: id,
      name: name,
      slug: slug,
      description: description,
      created_at: created_at,
      updated_at: updated_at
    )
  end

  # Create from domain entity
  def self.from_domain(team)
    new(
      id: team.id,
      name: team.name,
      slug: team.slug,
      description: team.description,
      created_at: team.created_at,
      updated_at: team.updated_at
    )
  end

  private

  def generate_slug
    self.slug = name.parameterize
  end
end
