# frozen_string_literal: true

require_relative "../../ports/storage_port"
require_relative "concerns/error_handler"

module Repositories
  # BaseMetricRepository provides core CRUD operations for all metrics
  # regardless of their source system
  class BaseMetricRepository
    include StoragePort
    include Repositories::Concerns::ErrorHandler

    def initialize(metric_naming_port: nil, logger_port: nil)
      @metric_naming_port = metric_naming_port || Adapters::Metrics::MetricNamingAdapter.new
      @logger_port = logger_port || Rails.logger
      @metrics_cache = {} # In-memory cache for tests
    end

    # Basic CRUD operations

    # Save a metric to the database
    # @param metric [Domain::Metric] The metric to save
    # @return [Domain::Metric] The saved metric with its ID
    def save_metric(metric)
      # Validate the metric
      validate_metric(metric)

      # Create a database record
      begin
        domain_metric = DomainMetric.create!(
          name: metric.name,
          value: metric.value,
          source: metric.source,
          dimensions: metric.dimensions,
          recorded_at: metric.timestamp
        )
      rescue StandardError => e
        handle_database_error("save", e, { metric_name: metric.name })
      end

      # Log the created metric ID
      log_debug("Created metric in database with ID: #{domain_metric.id}")

      # Update the domain metric with the database ID if needed
      if metric.id.nil? || metric.id.empty?
        log_debug("Updating metric with database ID: #{domain_metric.id}")
        metric = metric.with_id(domain_metric.id.to_s)
      end

      # Make sure we actually have an ID
      if metric.id.nil? || metric.id.empty?
        log_error("Metric still has nil/empty ID after save attempt")
        raise Repositories::Errors::ValidationError.new(
          "Failed to generate ID for metric",
          { metric_name: metric.name }
        )
      end

      # Store in memory cache for tests
      @metrics_cache[metric.id] = metric

      log_debug("Returning metric with ID: #{metric.id}")

      # Return the domain metric
      metric
    end

    # Find a metric by its ID
    # @param id [String, Integer] The metric ID
    # @return [Domain::Metric, nil] The metric or nil if not found
    def find_metric(id)
      # Log the ID we're trying to find
      log_debug("Finding metric with ID: #{id}")

      # Normalize the ID to string
      id_str = id.to_s

      # Try to find in memory cache first (for tests)
      if @metrics_cache.key?(id_str)
        log_debug("Found metric in cache: #{id_str}")
        return @metrics_cache[id_str]
      end

      # Delegate to the ActiveRecord model for database queries
      begin
        # Use the model's find_latest_by_id method (to be implemented in DomainMetric)
        domain_metric = DomainMetric.find_latest_by_id(id_str.to_i)

        # Return nil if not found
        unless domain_metric
          log_warn("Metric not found in database: #{id_str}")
          return nil
        end

        log_debug("Found metric in database: #{domain_metric.id} (#{domain_metric.name})")

        # Convert to domain model
        metric = to_domain_metric(domain_metric)

        # Cache for future lookups
        @metrics_cache[metric.id] = metric

        metric
      rescue StandardError => e
        handle_database_error("find", e, { id: id_str })
      end
    end

    # Update an existing metric
    # @param metric [Domain::Metric] The metric to update
    # @return [Domain::Metric] The updated metric
    def update_metric(metric)
      # Validate the metric
      validate_metric(metric)

      # Ensure we have an ID
      if metric.id.nil? || metric.id.empty?
        log_error("Cannot update metric without ID")
        return save_metric(metric) # Fall back to creating a new one
      end

      begin
        # Find the existing record
        domain_metric = DomainMetric.find_by_id_only(metric.id.to_i)

        unless domain_metric
          log_warn("Metric not found for update, creating new: #{metric.id}")
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
      rescue StandardError => e
        handle_database_error("update", e, { id: metric.id, metric_name: metric.name })
      end
    end

    # List metrics with optional filters
    # @param filters [Hash] Optional filters for name, source, time range, etc.
    # @return [Array<Domain::Metric>] Array of matching metrics
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
        to_domain_metric(domain_metric)
      end
    rescue StandardError => e
      handle_query_error("list_metrics", e, filters)
    end

    # Source-agnostic query methods

    # Find metrics by pattern matching components of the metric name
    # @param source [String, nil] Optional source system filter
    # @param entity [String, nil] Optional entity filter
    # @param action [String, nil] Optional action filter
    # @param detail [String, nil] Optional detail filter
    # @param start_time [Time, nil] Optional start time for filtering
    # @param end_time [Time, nil] Optional end time for filtering
    # @param dimensions [Hash, nil] Optional dimensions to filter by
    # @return [Array<Domain::Metric>] Array of matching metrics
    def find_by_pattern(source: nil, entity: nil, action: nil, detail: nil,
                        start_time: nil, end_time: nil, dimensions: nil)
      context = {
        source: source,
        entity: entity,
        action: action,
        detail: detail,
        start_time: start_time,
        end_time: end_time
      }

      begin
        # Build the query
        query = DomainMetric.all

        # Filter by metric name components if provided
        if source && entity && action
          metric_name = if detail
                          "#{source}.#{entity}.#{action}.#{detail}"
                        else
                          "#{source}.#{entity}.#{action}"
                        end
          query = query.where(name: metric_name)
        elsif source
          # Just filter by source prefix if only source is provided
          query = query.where("name LIKE ?", "#{source}.%")
        end

        # Add time range filters if provided
        query = query.where("recorded_at >= ?", start_time) if start_time
        query = query.where("recorded_at <= ?", end_time) if end_time

        # Add dimension filters if provided
        if dimensions.present?
          validate_dimensions(dimensions, context)
          normalized_dimensions = dimensions.transform_keys(&:to_s)
          query = query.where("dimensions @> ?", normalized_dimensions.to_json)
        end

        # Order by most recent first
        query = query.order(recorded_at: :desc)

        # Convert to domain models
        query.map do |domain_metric|
          to_domain_metric(domain_metric)
        end
      rescue StandardError => e
        handle_query_error("find_by_pattern", e, context)
      end
    end

    # Find metrics from a specific source system
    # @param source [String] The source system (github, bitbucket, jira, etc.)
    # @param start_time [Time, nil] Optional start time filter
    # @param end_time [Time, nil] Optional end time filter
    # @return [Array<Domain::Metric>] Array of metrics from the specified source
    def find_by_source(source, start_time: nil, end_time: nil)
      context = { source: source, start_time: start_time, end_time: end_time }

      begin
        query = DomainMetric.where("name LIKE ?", "#{source}.%")

        # Add time range filters if provided
        query = query.where("recorded_at >= ?", start_time) if start_time
        query = query.where("recorded_at <= ?", end_time) if end_time

        # Order by most recent first
        query = query.order(recorded_at: :desc)

        # Convert to domain models
        query.map do |domain_metric|
          to_domain_metric(domain_metric)
        end
      rescue StandardError => e
        handle_query_error("find_by_source", e, context)
      end
    end

    # Find metrics for a specific entity type
    # @param entity [String] The entity type (push, pull_request, issue, etc.)
    # @param start_time [Time, nil] Optional start time filter
    # @param end_time [Time, nil] Optional end time filter
    # @return [Array<Domain::Metric>] Array of metrics for the specified entity
    def find_by_entity(entity, start_time: nil, end_time: nil)
      context = { entity: entity, start_time: start_time, end_time: end_time }

      begin
        # This implementation assumes metrics follow the source.entity.action.detail pattern
        # We use a regex to match metrics where the entity is the second component
        query = DomainMetric.where("name ~ ?", "^[^.]+\\.#{entity}\\.")

        # Add time range filters if provided
        query = query.where("recorded_at >= ?", start_time) if start_time
        query = query.where("recorded_at <= ?", end_time) if end_time

        # Order by most recent first
        query = query.order(recorded_at: :desc)

        # Convert to domain models
        query.map do |domain_metric|
          to_domain_metric(domain_metric)
        end
      rescue StandardError => e
        handle_query_error("find_by_entity", e, context)
      end
    end

    # Find metrics for a specific action
    # @param action [String] The action (total, created, merged, etc.)
    # @param start_time [Time, nil] Optional start time filter
    # @param end_time [Time, nil] Optional end time filter
    # @return [Array<Domain::Metric>] Array of metrics for the specified action
    def find_by_action(action, start_time: nil, end_time: nil)
      context = { action: action, start_time: start_time, end_time: end_time }

      begin
        # This implementation assumes metrics follow the source.entity.action.detail pattern
        # We use a regex to match metrics where the action is the third component
        query = DomainMetric.where("name ~ ?", "^[^.]+\\.[^.]+\\.#{action}(\\.|$)")

        # Add time range filters if provided
        query = query.where("recorded_at >= ?", start_time) if start_time
        query = query.where("recorded_at <= ?", end_time) if end_time

        # Order by most recent first
        query = query.order(recorded_at: :desc)

        # Convert to domain models
        query.map do |domain_metric|
          to_domain_metric(domain_metric)
        end
      rescue StandardError => e
        handle_query_error("find_by_action", e, context)
      end
    end

    # Calculate statistical values from metrics

    # Get average value for metrics matching criteria
    # @param name [String] The metric name
    # @param start_time [Time, nil] Optional start time
    # @param end_time [Time, nil] Optional end time
    # @return [Float] The average value
    def get_average(name, start_time = nil, end_time = nil)
      context = { name: name, start_time: start_time, end_time: end_time }

      begin
        DomainMetric.average_for(name, start_time, end_time)
      rescue StandardError => e
        handle_query_error("get_average", e, context)
      end
    end

    # Get percentile value for metrics matching criteria
    # @param name [String] The metric name
    # @param percentile [Integer] The percentile (0-100)
    # @param start_time [Time, nil] Optional start time
    # @param end_time [Time, nil] Optional end time
    # @return [Float] The percentile value
    def get_percentile(name, percentile, start_time = nil, end_time = nil)
      context = {
        name: name,
        percentile: percentile,
        start_time: start_time,
        end_time: end_time
      }

      begin
        DomainMetric.percentile_for(name, percentile, start_time, end_time)
      rescue StandardError => e
        handle_query_error("get_percentile", e, context)
      end
    end

    # Find unique values for a dimension across metrics
    # @param metric_name [String] The metric name to filter by
    # @param dimensions [Hash] Dimensions to filter metrics by
    # @param value_field [String] The dimension field to get unique values for
    # @return [Array<String>] Unique values for the dimension field
    def find_unique_values(metric_name, dimensions, value_field)
      context = {
        metric_name: metric_name,
        dimensions: dimensions,
        value_field: value_field
      }

      begin
        # Validate dimensions
        validate_dimensions(dimensions, context)

        # Get all metrics matching criteria
        metrics = find_metrics_by_name_and_dimensions(metric_name, dimensions)

        # Extract and return unique values for the specified field
        metrics.map { |m| m.dimensions[value_field] }.uniq.compact
      rescue StandardError => e
        handle_query_error("find_unique_values", e, context)
      end
    end

    # Find metrics by name and dimensions
    # @param name [String] The metric name to search for
    # @param dimensions [Hash] The dimensions to filter by
    # @param start_time [Time] Optional start time to filter metrics
    # @return [Array<Domain::Metric>] Array of matching metrics
    def find_metrics_by_name_and_dimensions(name, dimensions, start_time = nil)
      context = {
        name: name,
        dimensions: dimensions,
        start_time: start_time
      }

      begin
        # Validate dimensions
        validate_dimensions(dimensions, context)

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
          to_domain_metric(domain_metric)
        end
      rescue StandardError => e
        handle_query_error("find_metrics_by_name_and_dimensions", e, context)
      end
    end

    # Find an aggregate metric by name and dimensions
    # @param name [String] The aggregate metric name
    # @param dimensions [Hash] The dimensions to match
    # @return [Domain::Metric, nil] The matching metric or nil if not found
    def find_aggregate_metric(name, dimensions)
      context = { name: name, dimensions: dimensions }

      begin
        # Validate dimensions
        validate_dimensions(dimensions, context)

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

        to_domain_metric(domain_metric)
      rescue StandardError => e
        handle_query_error("find_aggregate_metric", e, context)
      end
    end

    # List metrics with a name matching a pattern using SQL LIKE syntax
    # @param pattern [String] SQL LIKE pattern for the metric name
    # @param start_time [Time, nil] Optional start time filter
    # @param end_time [Time, nil] Optional end time filter
    # @return [Array<Domain::Metric>] Array of matching metrics
    def list_metrics_with_name_pattern(pattern, start_time: nil, end_time: nil)
      context = { pattern: pattern, start_time: start_time, end_time: end_time }

      begin
        log_info("Listing metrics with name pattern: #{pattern}, start_time: #{start_time}, end_time: #{end_time}")

        # Use the ActiveRecord query interface
        query = DomainMetric.where("name LIKE ?", pattern)

        # Add time constraints if provided
        query = query.where("recorded_at >= ?", start_time) if start_time
        query = query.where("recorded_at <= ?", end_time) if end_time

        # Execute the query and log the results
        metrics = query.to_a
        log_info("Found #{metrics.size} metrics matching pattern '#{pattern}'")

        # Convert to domain metrics
        metrics.map { |m| to_domain_metric(m) }
      rescue StandardError => e
        handle_query_error("list_metrics_with_name_pattern", e, context)
      end
    end

    # Helper methods
    protected

    # Convert a database record to a domain metric
    # @param domain_metric [DomainMetric] ActiveRecord metric
    # @return [Domain::Metric] Domain model metric
    def to_domain_metric(domain_metric)
      Domain::Metric.new(
        id: domain_metric.id.to_s,
        name: domain_metric.name,
        value: domain_metric.value.to_f,
        source: domain_metric.source,
        dimensions: domain_metric.dimensions || {},
        timestamp: domain_metric.recorded_at
      )
    end

    # Logging helper methods
    private

    def log_debug(message)
      if @logger_port.respond_to?(:debug)
        @logger_port.debug { message }
      else
        @logger_port.debug(message)
      end
    end

    def log_info(message)
      if @logger_port.respond_to?(:info)
        @logger_port.info { message }
      else
        @logger_port.info(message)
      end
    end

    def log_warn(message)
      if @logger_port.respond_to?(:warn)
        @logger_port.warn { message }
      else
        @logger_port.warn(message)
      end
    end

    def log_error(message)
      if @logger_port.respond_to?(:error)
        @logger_port.error { message }
      else
        @logger_port.error(message)
      end
    end
  end
end
