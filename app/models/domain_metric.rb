# frozen_string_literal: true

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
  scope :with_source, ->(source) { where(source: source) if source.present? }
  scope :since, ->(timestamp) { where("recorded_at >= ?", timestamp) if timestamp.present? }
  scope :until, ->(timestamp) { where("recorded_at <= ?", timestamp) if timestamp.present? }
  scope :between, lambda { |start_time, end_time|
    scope = all
    scope = scope.where("recorded_at >= ?", start_time) if start_time.present?
    scope = scope.where("recorded_at <= ?", end_time) if end_time.present?
    scope
  }
  scope :latest_first, -> { order(recorded_at: :desc) }

  # Scope for filtering by dimensions (uses GIN index with @> operator)
  scope :with_dimensions, lambda { |dimensions|
    return all if dimensions.blank?

    normalized_dimensions = dimensions.transform_keys(&:to_s)
    where("dimensions @> ?", normalized_dimensions.to_json)
  }

  # Efficiently find the latest metric by ID handling the JSONB dimensions column
  # @param id [Integer, String] The ID of the metric to find
  # @return [DomainMetric, nil] The found metric or nil if not found
  def self.find_latest_by_id(id)
    return nil if id.nil?

    # Ensure we're working with an integer ID
    id_int = id.is_a?(String) ? id.to_i : id

    Rails.logger.debug { "Finding latest metric with ID: #{id_int}" }

    # Use a single efficient query to get the latest metric with this ID
    # and properly handle the JSONB dimensions column
    metric = select("id, name, value, source, dimensions, recorded_at")
             .where(id: id_int)
             .order(recorded_at: :desc)
             .limit(1)
             .first

    if metric
      # Ensure dimensions are accessible as a hash
      # PostgreSQL returns JSONB as a hash already, but let's handle it safely
      dimensions = metric.dimensions || {}
      metric.dimensions_hash = dimensions.is_a?(Hash) ? dimensions : {}

      Rails.logger.debug { "Found latest metric: #{metric.id} (#{metric.name})" }
    else
      Rails.logger.debug { "No metric found with ID: #{id_int}" }
    end

    metric
  end

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

  # Get dimensions as a hash, handling both accessor and database column
  # @return [Hash] The dimensions as a hash
  def dimensions
    # Return the accessor value if set
    return dimensions_hash if dimensions_hash.present?

    # Otherwise try to parse from the database column
    db_dimensions = read_attribute(:dimensions)
    if db_dimensions.present?
      # If it's already a hash, return it
      return db_dimensions if db_dimensions.is_a?(Hash)

      # Otherwise try to parse it
      begin
        JSON.parse(db_dimensions.to_s)
      rescue JSON::ParserError => e
        Rails.logger.error { "Failed to parse dimensions JSON: #{e.message}" }
        {}
      end
    else
      {}
    end
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

  # List metrics with various filtering options
  # @param name [String, nil] Filter by metric name
  # @param source [String, nil] Filter by metric source
  # @param start_time [Time, nil] Filter metrics since this time
  # @param end_time [Time, nil] Filter metrics until this time
  # @param dimensions [Hash, nil] Filter by specific dimensions
  # @param latest_first [Boolean] Order by most recent first
  # @param limit [Integer, nil] Limit the number of results
  # @return [ActiveRecord::Relation] Collection of metric records
  def self.list_metrics(name: nil, source: nil, start_time: nil, end_time: nil, dimensions: nil, latest_first: nil,
                        limit: nil)
    # Start with a base query
    query = all

    # Apply filters - order matters for index usage!
    query = query.with_name(name) if name
    query = query.with_source(source) if source
    query = query.between(start_time, end_time) if start_time || end_time
    query = query.with_dimensions(dimensions) if dimensions
    query = query.latest_first if latest_first
    query = query.limit(limit) if limit

    # Log what we're doing
    Rails.logger.debug do
      "Listing metrics with filters: name=#{name}, source=#{source}, start_time=#{start_time}, end_time=#{end_time}, dimensions=#{dimensions&.inspect}, latest_first=#{latest_first}, limit=#{limit}"
    end

    # Return the query result
    query
  end

  # Find metrics with name pattern (useful for aggregation jobs)
  # @param name_pattern [String] SQL LIKE pattern for metric names
  # @param start_time [Time, nil] Filter metrics since this time
  # @param end_time [Time, nil] Filter metrics until this time
  # @return [ActiveRecord::Relation] Collection of metrics
  def self.with_name_pattern(name_pattern, start_time = nil, end_time = nil)
    # Base query
    query = where("name LIKE ?", name_pattern)

    # Add time filters
    query = query.since(start_time) if start_time
    query = query.until(end_time) if end_time

    query
  end

  # Find metrics with efficient use of composite index
  # @param name [String] The metric name
  # @param source [String, nil] Optional source filter
  # @param start_time [Time, nil] Optional start time
  # @param end_time [Time, nil] Optional end time
  # @return [ActiveRecord::Relation] Collection of metrics
  def self.find_by_name_source_time(name, source = nil, start_time = nil, end_time = nil)
    # Start with name to use the composite index prefix
    query = with_name(name)

    # Add source filter if provided (uses second column in composite index)
    query = query.with_source(source) if source.present?

    # Add time filters (uses third column in composite index)
    query = query.between(start_time, end_time) if start_time || end_time

    query
  end
end
