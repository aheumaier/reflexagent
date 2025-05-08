# frozen_string_literal: true

# CodeRepository ActiveRecord model that maps to the code_repositories table
class CodeRepository < ApplicationRecord
  belongs_to :team, optional: true

  validates :name, presence: true
  validates :provider, presence: true
  validates :name, uniqueness: { scope: :provider }

  scope :by_provider, ->(provider) { where(provider: provider) }
  scope :by_team, ->(team_id) { where(team_id: team_id) }
  scope :orphaned, -> { where(team_id: nil) }

  # Convert to domain entity
  def to_domain
    Domain::CodeRepository.new(
      id: id,
      name: name,
      url: url,
      provider: provider,
      team_id: team_id,
      created_at: created_at,
      updated_at: updated_at
    )
  end

  # Create from domain entity
  def self.from_domain(repo)
    new(
      id: repo.id,
      name: repo.name,
      url: repo.url,
      provider: repo.provider,
      team_id: repo.team_id,
      created_at: repo.created_at,
      updated_at: repo.updated_at
    )
  end

  # Extract owner/org name from full repository name
  def owner
    parts = name.to_s.split("/")
    parts.size >= 2 ? parts[0] : nil
  end

  # Extract repository name from full repository name
  def repo_name
    parts = name.to_s.split("/")
    parts.size >= 2 ? parts[1..-1].join("/") : name
  end
end
