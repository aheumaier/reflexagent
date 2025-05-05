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

      # Find the existing record
      domain_metric = DomainMetric.find_by_id_only(metric.id.to_i)

      unless domain_metric
        Rails.logger.warn { "Metric not found for update, creating new: #{metric.id}" }
        return save_metric(metric)
      end

      # Update the record
      domain_metric.update!(
        name: metric.name,
        value: metric.value,
        source: metric.source,
        dimensions: metric.dimensions,
        recorded_at: metric.timestamp
      )

      # Update cache
      @metrics_cache[metric.id] = metric

      # Return the updated metric
      metric
    end

    def find_unique_values(metric_name, dimensions, value_field)
      # Get all metrics matching criteria
      metrics = find_metrics_by_name_and_dimensions(metric_name, dimensions)

      # Extract and return unique values for the specified field
      metrics.map { |m| m.dimensions[value_field] }.uniq.compact
    end

    # Implement commit metrics analysis methods

    # Find hotspot directories for the given time period
    # @param since [Time] The start time for analysis
    # @param repository [String, nil] Optional repository filter
    # @param limit [Integer] Maximum number of results to return
    # @return [Array<Hash>] Array of directory hotspots with counts
    def hotspot_directories(since:, repository: nil, limit: 10)
      base_query = CommitMetric.since(since)
      base_query = base_query.by_repository(repository) if repository.present?

      Rails.logger.debug { "Finding hotspot directories since #{since}" }

      # Get hotspot directories from the CommitMetric model
      hotspots = base_query.hotspot_directories(since: since, limit: limit)

      # Format the results as hashes
      hotspots.map do |hotspot|
        {
          directory: hotspot.directory,
          count: hotspot.change_count
        }
      end
    end

    # Find hotspot file types for the given time period
    # @param since [Time] The start time for analysis
    # @param repository [String, nil] Optional repository filter
    # @param limit [Integer] Maximum number of results to return
    # @return [Array<Hash>] Array of file type hotspots with counts
    def hotspot_filetypes(since:, repository: nil, limit: 10)
      base_query = CommitMetric.since(since)
      base_query = base_query.by_repository(repository) if repository.present?

      Rails.logger.debug { "Finding hotspot filetypes since #{since}" }

      # Get hotspot file types from the CommitMetric model
      hotspots = base_query.hotspot_files_by_extension(since: since, limit: limit)

      # Format the results as hashes
      hotspots.map do |hotspot|
        {
          filetype: hotspot.filetype,
          count: hotspot.change_count
        }
      end
    end

    # Find distribution of commit types for the given time period
    # @param since [Time] The start time for analysis
    # @param repository [String, nil] Optional repository filter
    # @return [Array<Hash>] Array of commit types with counts
    def commit_type_distribution(since:, repository: nil)
      base_query = CommitMetric.since(since)
      base_query = base_query.by_repository(repository) if repository.present?

      Rails.logger.debug { "Finding commit type distribution since #{since}" }

      # Get commit type distribution from the CommitMetric model
      distribution = base_query.commit_type_distribution(since: since)

      # Format the results as hashes
      distribution.map do |type|
        {
          type: type.commit_type,
          count: type.count
        }
      end
    end

    # Find most active authors for the given time period
    # @param since [Time] The start time for analysis
    # @param repository [String, nil] Optional repository filter
    # @param limit [Integer] Maximum number of results to return
    # @return [Array<Hash>] Array of authors with commit counts
    def author_activity(since:, repository: nil, limit: 10)
      base_query = CommitMetric.since(since)
      base_query = base_query.by_repository(repository) if repository.present?

      Rails.logger.debug { "Finding author activity since #{since}" }

      # Get author activity from the CommitMetric model
      authors = base_query.author_activity(since: since, limit: limit)

      # Format the results as hashes
      authors.map do |author|
        {
          author: author.author,
          commit_count: author.commit_count
        }
      end
    end

    # Find lines changed by author for the given time period
    # @param since [Time] The start time for analysis
    # @param repository [String, nil] Optional repository filter
    # @return [Array<Hash>] Array of authors with lines added/removed
    def lines_changed_by_author(since:, repository: nil)
      base_query = CommitMetric.since(since)
      base_query = base_query.by_repository(repository) if repository.present?

      Rails.logger.debug { "Finding lines changed by author since #{since}" }

      # Get lines changed by author from the CommitMetric model
      authors = base_query.lines_changed_by_author(since: since)

      # Format the results as hashes
      authors.map do |author|
        {
          author: author.author,
          lines_added: author.lines_added.to_i,
          lines_deleted: author.lines_deleted.to_i,
          lines_changed: author.lines_added.to_i + author.lines_deleted.to_i
        }
      end
    end

    # Find breaking changes by author for the given time period
    # @param since [Time] The start time for analysis
    # @param repository [String, nil] Optional repository filter
    # @return [Array<Hash>] Array of authors with breaking change counts
    def breaking_changes_by_author(since:, repository: nil)
      base_query = CommitMetric.since(since)
      base_query = base_query.by_repository(repository) if repository.present?

      Rails.logger.debug { "Finding breaking changes by author since #{since}" }

      # Get breaking changes by author from the CommitMetric model
      authors = base_query.breaking_changes_by_author(since: since)

      # Format the results as hashes
      authors.map do |author|
        {
          author: author.author,
          breaking_count: author.breaking_count
        }
      end
    end

    # Find commit activity by day for the given time period
    # @param since [Time] The start time for analysis
    # @param repository [String, nil] Optional repository filter
    # @return [Array<Hash>] Array of days with commit counts
    def commit_activity_by_day(since:, repository: nil)
      base_query = CommitMetric.since(since)
      base_query = base_query.by_repository(repository) if repository.present?

      Rails.logger.debug { "Finding commit activity by day since #{since}" }

      # Get commit activity by day from the CommitMetric model
      activity = base_query.commit_activity_by_day(since: since)

      # Format the results as hashes
      activity.map do |day|
        {
          date: day.day,
          commit_count: day.commit_count
        }
      end
    end
  end
end
