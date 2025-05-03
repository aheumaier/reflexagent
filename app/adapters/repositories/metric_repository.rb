# frozen_string_literal: true

require_relative "../../ports/storage_port"

module Repositories
  class MetricRepository
    include StoragePort

    def initialize
      @metrics_cache = {} # In-memory cache for tests
    end

    def save_metric(metric)
      # Create a database record
      domain_metric = DomainMetric.create!(
        name: metric.name,
        value: metric.value,
        source: metric.source,
        dimensions: metric.dimensions,
        recorded_at: metric.timestamp
      )

      # Log the created metric ID
      Rails.logger.debug { "Created metric in database with ID: #{domain_metric.id}" }

      # Update the domain metric with the database ID if needed
      if metric.id.nil? || metric.id.empty?
        Rails.logger.debug { "Updating metric with database ID: #{domain_metric.id}" }
        metric = metric.with_id(domain_metric.id.to_s)
      end

      # Make sure we actually have an ID
      Rails.logger.error { "Metric still has nil/empty ID after save attempt" } if metric.id.nil? || metric.id.empty?

      # Store in memory cache for tests
      @metrics_cache[metric.id] = metric

      Rails.logger.debug { "Returning metric with ID: #{metric.id}" }

      # Return the domain metric
      metric
    end

    def find_metric(id)
      # Log the ID we're trying to find
      Rails.logger.debug { "Finding metric with ID: #{id}" }

      # Normalize the ID to string
      id_str = id.to_s

      # Try to find in memory cache first (for tests)
      if @metrics_cache.key?(id_str)
        Rails.logger.debug { "Found metric in cache: #{id_str}" }
        return @metrics_cache[id_str]
      end

      # Find in database - for composite primary key, we need to use find_by
      begin
        # Get a fresh database connection from the pool
        ActiveRecord::Base.connection_pool.with_connection do |conn|
          # Since metrics has a composite primary key (id, recorded_at),
          # we need a more specific approach
          Rails.logger.debug { "Using composite key approach for metric lookup" }

          # Try to find by ID only (ignoring the recorded_at part of composite key)
          domain_metric = DomainMetric.find_by_id_only(id_str.to_i)

          # If not found, try a direct query
          if domain_metric.nil?
            Rails.logger.debug { "Trying direct query for metric ID: #{id_str.to_i}" }
            begin
              id_int = id_str.to_i
              sql = "SELECT id, name, value, source, dimensions::text as dimensions_text, recorded_at FROM metrics WHERE id = ? ORDER BY recorded_at DESC LIMIT 1"
              result = conn.exec_query(sql, "Direct Metric Lookup", [id_int])

              if result.rows.any?
                # Parse the results
                record = result.to_a.first

                # Parse JSONB data
                dimensions = {}
                if record["dimensions_text"].present?
                  begin
                    dimensions = JSON.parse(record["dimensions_text"])
                  rescue JSON::ParserError => e
                    Rails.logger.error { "Failed to parse dimensions JSON: #{e.message}" }
                    dimensions = {}
                  end
                end

                # Create the domain model directly
                metric = Domain::Metric.new(
                  id: record["id"].to_s,
                  name: record["name"],
                  value: record["value"].to_f,
                  source: record["source"],
                  dimensions: dimensions,
                  timestamp: record["recorded_at"]
                )

                # Cache for future lookups
                @metrics_cache[metric.id] = metric

                Rails.logger.debug { "Created metric from direct SQL: #{metric.id} (#{metric.name})" }
                return metric
              end
            rescue StandardError => e
              Rails.logger.error { "Error in direct database query: #{e.message}" }
              Rails.logger.error { e.backtrace.join("\n") }
            end
          end

          unless domain_metric
            Rails.logger.warn { "Metric not found in database: #{id_str}" }
            return nil
          end

          Rails.logger.debug { "Found metric in database: #{domain_metric.id} (#{domain_metric.name})" }

          # Convert to domain model
          metric = Domain::Metric.new(
            id: domain_metric.id.to_s,
            name: domain_metric.name,
            value: domain_metric.value,
            source: domain_metric.source,
            dimensions: domain_metric.dimensions || {},
            timestamp: domain_metric.recorded_at
          )

          # Cache for future lookups
          @metrics_cache[metric.id] = metric

          return metric
        end
      rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordNotFound => e
        Rails.logger.error { "Database error finding metric #{id_str}: #{e.message}" }
        nil
      end
    end

    def list_metrics(filters = {})
      # Start with a base query
      query = DomainMetric.all

      # Apply filters
      query = query.with_name(filters[:name]) if filters[:name]
      query = query.since(filters[:start_time]) if filters[:start_time]
      query = query.until(filters[:end_time]) if filters[:end_time]
      query = query.latest_first if filters[:latest_first]
      query = query.limit(filters[:limit]) if filters[:limit]

      # Convert to domain models
      query.map do |domain_metric|
        Domain::Metric.new(
          id: domain_metric.id.to_s,
          name: domain_metric.name,
          value: domain_metric.value,
          source: domain_metric.source,
          dimensions: domain_metric.dimensions || {},
          timestamp: domain_metric.recorded_at
        )
      end
    end

    def get_average(name, start_time = nil, end_time = nil)
      DomainMetric.average_for(name, start_time, end_time)
    end

    def get_percentile(name, percentile, start_time = nil, end_time = nil)
      DomainMetric.percentile_for(name, percentile, start_time, end_time)
    end

    # New method to find metrics by name and dimensions
    # @param name [String] The metric name to search for
    # @param dimensions [Hash] The dimensions to filter by
    # @param start_time [Time] Optional start time to filter metrics
    # @return [Array<Domain::Metric>] Array of matching metrics
    def find_metrics_by_name_and_dimensions(name, dimensions, start_time = nil)
      # Start with a base query for the name
      query = DomainMetric.where(name: name)

      # Add dimension filters using PostgreSQL JSONB containment operator
      # This ensures we find metrics where dimensions contain at least the provided key-value pairs
      if dimensions.present?
        normalized_dimensions = dimensions.transform_keys(&:to_s)
        query = query.where("dimensions @> ?", normalized_dimensions.to_json)
      end

      # Add time range if provided
      query = query.where("recorded_at >= ?", start_time) if start_time

      # Order by most recent first
      query = query.order(recorded_at: :desc)

      # Convert to domain models
      query.map do |domain_metric|
        Domain::Metric.new(
          id: domain_metric.id.to_s,
          name: domain_metric.name,
          value: domain_metric.value,
          source: domain_metric.source,
          dimensions: domain_metric.dimensions || {},
          timestamp: domain_metric.recorded_at
        )
      end
    end

    # Find an aggregate metric by name and dimensions
    # @param name [String] The aggregate metric name
    # @param dimensions [Hash] The dimensions to match
    # @return [Domain::Metric, nil] The matching metric or nil if not found
    def find_aggregate_metric(name, dimensions)
      # Normalize dimensions for search
      normalized_dimensions = dimensions.transform_keys(&:to_s)

      # Start with a query for metrics with this name
      domain_metrics = DomainMetric.where(name: name)

      # Filter by exact dimension match using PostgreSQL JSONB containment operators
      # We want the dimensions to exactly match both ways (metric contains all dims AND dims contain all metric)
      domain_metrics = domain_metrics.where(
        "dimensions @> ? AND ? @> dimensions",
        normalized_dimensions.to_json,
        normalized_dimensions.to_json
      )

      # Get the most recent one
      domain_metric = domain_metrics.order(recorded_at: :desc).first

      # If found, convert to domain model and return
      return nil unless domain_metric

      Domain::Metric.new(
        id: domain_metric.id.to_s,
        name: domain_metric.name,
        value: domain_metric.value,
        source: domain_metric.source,
        dimensions: domain_metric.dimensions || {},
        timestamp: domain_metric.recorded_at
      )
    end

    # Update an existing metric
    # @param metric [Domain::Metric] The metric to update
    # @return [Domain::Metric] The updated metric
    def update_metric(metric)
      # Ensure we have an ID
      if metric.id.nil? || metric.id.empty?
        Rails.logger.error { "Cannot update metric without ID" }
        return save_metric(metric) # Fall back to creating a new one
      end

      # Find the database record
      begin
        domain_metric = DomainMetric.find_by_id_only(metric.id.to_i)

        if domain_metric
          # Update the values
          domain_metric.update!(
            value: metric.value,
            dimensions: metric.dimensions,
            recorded_at: metric.timestamp
          )

          # Update the cache
          @metrics_cache[metric.id] = metric

          Rails.logger.debug { "Updated metric: #{metric.id} (#{metric.name})" }
          metric
        else
          # If not found, create a new one
          Rails.logger.warn { "Metric #{metric.id} not found for update, creating new" }
          save_metric(metric)
        end
      rescue StandardError => e
        Rails.logger.error { "Error updating metric #{metric.id}: #{e.message}" }
        Rails.logger.error { e.backtrace.join("\n") }
        save_metric(metric) # Fall back to creating a new one
      end
    end

    # Find unique values for a particular field in metric dimensions
    # @param metric_name [String] The metric name to search in
    # @param dimensions [Hash] Base dimensions to filter by
    # @param value_field [String] The dimension field to extract unique values from
    # @return [Array] Array of unique values
    def find_unique_values(metric_name, dimensions, value_field)
      # Get all metrics matching criteria
      metrics = find_metrics_by_name_and_dimensions(metric_name, dimensions)

      # Extract unique values for the specified field
      metrics.map { |m| m.dimensions[value_field.to_s] || m.dimensions[value_field.to_sym] }
             .compact
             .uniq
    end
  end
end
