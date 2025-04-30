class DomainMetric < ApplicationRecord
  self.table_name = 'metrics'

  validates :name, presence: true
  validates :value, presence: true
  validates :recorded_at, presence: true

  # Scopes for efficient querying
  scope :with_name, ->(name) { where(name: name) }
  scope :since, ->(timestamp) { where('recorded_at >= ?', timestamp) }
  scope :until, ->(timestamp) { where('recorded_at <= ?', timestamp) }
  scope :between, ->(start_time, end_time) { where(recorded_at: start_time..end_time) }
  scope :latest_first, -> { order(recorded_at: :desc) }

  # Class methods for analytics
  def self.average_for(name, start_time = nil, end_time = nil)
    scope = with_name(name)
    scope = scope.between(start_time, end_time) if start_time && end_time
    scope.average(:value)
  end

  def self.percentile_for(name, percentile, start_time = nil, end_time = nil)
    scope = with_name(name)
    scope = scope.between(start_time, end_time) if start_time && end_time

    # Simplified percentile calculation for PostgreSQL
    # In a real implementation, you might use a more sophisticated approach
    # or leverage PostgreSQL's percentile_cont function
    values = scope.pluck(:value).sort
    return nil if values.empty?

    k = (percentile / 100.0) * (values.size - 1)
    f = k.floor
    c = k.ceil

    if f == c
      values[f]
    else
      (values[f] * (c - k) + values[c] * (k - f))
    end
  end
end
