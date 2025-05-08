# frozen_string_literal: true

require_relative "../../ports/storage_port"

module Repositories
  class MetricRepository
    include StoragePort

    def initialize(logger_port: nil)
      @metrics_cache = {} # In-memory cache for tests
      @logger_port = logger_port || Rails.logger
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
      @logger_port.debug { "Created metric in database with ID: #{domain_metric.id}" }

      # Update the domain metric with the database ID if needed
      if metric.id.nil? || metric.id.empty?
        @logger_port.debug { "Updating metric with database ID: #{domain_metric.id}" }
        metric = metric.with_id(domain_metric.id.to_s)
      end

      # Make sure we actually have an ID
      @logger_port.error { "Metric still has nil/empty ID after save attempt" } if metric.id.nil? || metric.id.empty?

      # Store in memory cache for tests
      @metrics_cache[metric.id] = metric

      @logger_port.debug { "Returning metric with ID: #{metric.id}" }

      # Return the domain metric
      metric
    end

    def find_metric(id)
      # Log the ID we're trying to find
      @logger_port.debug { "Finding metric with ID: #{id}" }

      # Normalize the ID to string
      id_str = id.to_s

      # Try to find in memory cache first (for tests)
      if @metrics_cache.key?(id_str)
        @logger_port.debug { "Found metric in cache: #{id_str}" }
        return @metrics_cache[id_str]
      end

      # Delegate to the ActiveRecord model for database queries
      begin
        # Use the model's find_latest_by_id method (to be implemented in DomainMetric)
        domain_metric = DomainMetric.find_latest_by_id(id_str.to_i)

        # Return nil if not found
        unless domain_metric
          @logger_port.warn { "Metric not found in database: #{id_str}" }
          return nil
        end

        @logger_port.debug { "Found metric in database: #{domain_metric.id} (#{domain_metric.name})" }

        # Convert to domain model
        metric = Domain::Metric.new(
          id: domain_metric.id.to_s,
          name: domain_metric.name,
          value: domain_metric.value.to_f,
          source: domain_metric.source,
          dimensions: domain_metric.dimensions || {},
          timestamp: domain_metric.recorded_at
        )

        # Cache for future lookups
        @metrics_cache[metric.id] = metric

        metric
      rescue StandardError => e
        @logger_port.error { "Database error finding metric #{id_str}: #{e.message}" }
        @logger_port.error { e.backtrace.join("\n") }
        nil
      end
    end

    def list_metrics(filters = {})
      # Delegate to the ActiveRecord model's list_metrics class method
      domain_metrics = DomainMetric.list_metrics(
        name: filters[:name],
        source: filters[:source],
        start_time: filters[:start_time],
        end_time: filters[:end_time],
        dimensions: filters[:dimensions],
        latest_first: filters[:latest_first],
        limit: filters[:limit]
      )

      # Convert to domain models
      domain_metrics.map do |domain_metric|
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
        @logger_port.error { "Cannot update metric without ID" }
        return save_metric(metric) # Fall back to creating a new one
      end

      # Find the existing record
      domain_metric = DomainMetric.find_by_id_only(metric.id.to_i)

      unless domain_metric
        @logger_port.warn { "Metric not found for update, creating new: #{metric.id}" }
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

      @logger_port.debug { "Finding hotspot directories since #{since}" }

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

      @logger_port.debug { "Finding hotspot filetypes since #{since}" }

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

      @logger_port.debug { "Finding commit type distribution since #{since}" }

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

      @logger_port.debug { "Finding author activity since #{since}" }

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

      @logger_port.debug { "Finding lines changed by author since #{since}" }

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

      @logger_port.debug { "Finding breaking changes by author since #{since}" }

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

      @logger_port.debug { "Finding commit activity by day since #{since}" }

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

    # Get active repositories with optimized DB-level aggregation
    # @param start_time [Time] The start time for filtering activity
    # @param limit [Integer] Maximum number of repositories to return
    # @param page [Integer] Page number for pagination
    # @param per_page [Integer] Items per page for pagination
    # @return [Array<String>] List of repository names
    def get_active_repositories(start_time:, limit: 50, page: nil, per_page: nil)
      @logger_port.debug { "Getting active repositories since #{start_time}" }

      # Create a raw SQL query that efficiently aggregates repositories at the database level
      # This avoids loading all metrics into memory
      sql = <<-SQL
        SELECT DISTINCT jsonb_extract_path_text(dimensions, 'repository') AS repository_name,
               COUNT(*) AS push_count
        FROM metrics
        WHERE name = 'github.push.total'
          AND recorded_at >= ?
          AND dimensions @> '{"repository": {}}'::jsonb
        GROUP BY repository_name
        ORDER BY push_count DESC, repository_name ASC
      SQL

      # Apply pagination or limit
      if page && per_page
        offset = (page - 1) * per_page
        sql += " LIMIT ? OFFSET ?"
        params = [start_time, per_page, offset]
      else
        sql += " LIMIT ?"
        params = [start_time, limit]
      end

      # Execute the query directly for better performance
      result = ActiveRecord::Base.connection.exec_query(sql, "Get Active Repositories", params)

      # Extract repository names from the result
      result.map { |row| row["repository_name"] }.compact
    rescue StandardError => e
      @logger_port.error { "Error fetching active repositories: #{e.message}" }
      @logger_port.error { e.backtrace.join("\n") }
      # Fallback to empty array on error
      []
    end

    # New method for direct database lookup of metrics by ID
    # @param id_int [Integer] The integer ID of the metric to find
    # @return [Domain::Metric, nil] The found metric or nil if not found
    def find_metric_direct(id_int)
      @logger_port.debug { "Direct database lookup for metric ID: #{id_int}" }

      # Try using our direct database method first
      begin
        domain_metric = DomainMetric.find_by_id_direct(id_int)

        if domain_metric
          @logger_port.debug { "Found metric via find_by_id_direct: #{domain_metric.id} (#{domain_metric.name})" }
          metric = Domain::Metric.new(
            id: domain_metric.id.to_s,
            name: domain_metric.name,
            value: domain_metric.value.to_f,
            source: domain_metric.source,
            dimensions: domain_metric.dimensions_hash || {},
            timestamp: domain_metric.recorded_at
          )

          # Cache for future lookups
          @metrics_cache[metric.id] = metric

          return metric
        end

        # Fallback to raw SQL as a last resort
        ActiveRecord::Base.connection_pool.with_connection do |conn|
          # Use direct SQL query as a last resort, getting only the most recent metric
          sql = "SELECT id, name, value, source, dimensions::text as dimensions_text, recorded_at FROM metrics WHERE id = ? ORDER BY recorded_at DESC LIMIT 1"

          # Use safer parameter binding
          result = conn.exec_query(sql, "Direct Metric Lookup", [id_int])

          if result.rows.any?
            record = result.to_a.first

            # Parse the JSONB dimensions field
            dimensions = {}
            if record["dimensions_text"].present?
              begin
                dimensions = JSON.parse(record["dimensions_text"])
              rescue JSON::ParserError => e
                @logger_port.error { "Failed to parse dimensions JSON: #{e.message}" }
                dimensions = {}
              end
            end

            # Create the domain metric directly
            @logger_port.debug { "Found metric via direct SQL: #{record['id']} (#{record['name']})" }
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

            return metric
          end
        end
      rescue StandardError => e
        @logger_port.error { "Error in direct metric lookup: #{e.message}" }
        @logger_port.error { e.backtrace.join("\n") }
      end

      nil
    end
  end
end
