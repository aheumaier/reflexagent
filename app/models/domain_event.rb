class DomainEvent < ApplicationRecord
  validates :aggregate_id, presence: true
  validates :event_type, presence: true
  validates :payload, presence: true

  # Scopes for easier querying
  scope :for_aggregate, ->(aggregate_id) { where(aggregate_id: aggregate_id) }
  scope :of_type, ->(event_type) { where(event_type: event_type) }
  scope :since_position, ->(position) { where("position > ?", position) }
  scope :chronological, -> { order(:position) }
end
