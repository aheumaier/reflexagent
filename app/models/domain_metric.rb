class DomainMetric < ApplicationRecord
  self.table_name = "metrics"

  # Since our metrics table has a composite primary key (id, recorded_at),
  # we need to be careful in how we handle it
  self.primary_key = "id"

  # Make dimensions accessible
  attr_accessor :dimensions_hash

  validates :name, presence: true
  validates :value, presence: true
  validates :recorded_at, presence: true

  # Scopes for efficient querying
  scope :with_name, ->(name) { where(name: name) }
  scope :since, ->(timestamp) { where("recorded_at >= ?", timestamp) }
  scope :until, ->(timestamp) { where("recorded_at <= ?", timestamp) }
  scope :between, ->(start_time, end_time) { where(recorded_at: start_time..end_time) }
  scope :latest_first, -> { order(recorded_at: :desc) }

  # Method to find by ID only (getting the most recent record when multiple records have the same ID)
  # This is useful for when we only have the ID part of the composite key
  def self.find_by_id_only(id)
    return nil if id.nil?

    # Ensure we're working with an integer ID
    id_int = id.is_a?(String) ? id.to_i : id

    # Log what we're looking for
    Rails.logger.debug { "Looking for metric with ID: #{id_int} (find_by_id_only)" }

    # Get the most recent entry with this ID
    result = where(id: id_int).order(recorded_at: :desc).first

    if result
      Rails.logger.debug { "Found metric: #{result.id} (#{result.name})" }
    else
      Rails.logger.debug { "No metric found with ID: #{id_int}" }
    end

    result
  end

  # Direct database accessor to avoid ActiveRecord issues with composite keys
  def self.find_by_id_direct(id)
    return nil if id.nil?

    id_int = id.is_a?(String) ? id.to_i : id
    Rails.logger.debug { "Direct DB lookup for metric ID: #{id_int}" }

    begin
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        sql = "SELECT id, name, value, source, dimensions::text as dimensions_text, recorded_at FROM metrics WHERE id = $1 ORDER BY recorded_at DESC LIMIT 1"
        result = conn.exec_query(sql, "Direct Metric Lookup", [id_int])

        if result.rows.any?
          record = result.to_a.first.symbolize_keys

          # Parse the JSONB dimensions field
          dimensions = {}
          if record[:dimensions_text].present?
            begin
              dimensions = JSON.parse(record[:dimensions_text])
            rescue JSON::ParserError => e
              Rails.logger.error { "Failed to parse dimensions JSON: #{e.message}" }
              dimensions = {}
            end
          end

          # Create DomainMetric with parsed dimensions
          domain_metric = new({
                                id: record[:id],
                                name: record[:name],
                                value: record[:value],
                                source: record[:source],
                                recorded_at: record[:recorded_at]
                              })
          domain_metric.dimensions_hash = dimensions
          domain_metric
        else
          nil
        end
      end
    rescue StandardError => e
      Rails.logger.error { "Error in direct lookup: #{e.message}" }
      nil
    end
  end

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
      ((values[f] * (c - k)) + (values[c] * (k - f)))
    end
  end
end
