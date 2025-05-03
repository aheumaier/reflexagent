# frozen_string_literal: true

module UseCases
  # CalculateMetrics is responsible for generating metrics from events
  # It uses MetricClassifier to determine which metrics to create for each event
  class CalculateMetrics
    def initialize(storage_port:, cache_port:, metric_classifier:)
      @storage_port = storage_port
      @cache_port = cache_port
      @metric_classifier = metric_classifier
    end

    def call(event_id)
      # Log the event ID we're trying to process
      Rails.logger.debug { "CalculateMetrics.call for event ID: #{event_id}" }

      # Try to find the event
      event = @storage_port.find_event(event_id)

      # Check if we found an event
      unless event
        Rails.logger.warn { "Event with ID #{event_id} not found in calculate_metrics" }
        raise NoMethodError, "Event with ID #{event_id} not found"
      end

      Rails.logger.debug { "Found event: #{event.id} (#{event.name})" }

      # Use the metric classifier to determine which metrics to create
      classification = @metric_classifier.classify_event(event)

      # Create and save each metric
      saved_metrics = process_metrics(classification[:metrics], event)

      Rails.logger.debug { "Created #{saved_metrics.size} metrics from event: #{event.id}" }

      # If only one metric was created, return it for backward compatibility
      # Otherwise, return the array of metrics
      saved_metrics.size == 1 ? saved_metrics.first : saved_metrics
    end

    private

    def process_metrics(metric_definitions, event)
      metric_definitions.map do |metric_def|
        create_and_save_metric(metric_def, event)
      end
    end

    def create_and_save_metric(metric_def, event)
      # Create the domain metric
      metric = Domain::Metric.new(
        name: metric_def[:name],
        value: metric_def[:value],
        source: event.source,
        dimensions: metric_def[:dimensions],
        timestamp: Time.now
      )

      # Save and get the metric with an ID
      saved_metric = @storage_port.save_metric(metric)

      # Ensure the metric has an ID before caching
      if saved_metric.id.nil?
        Rails.logger.error("Metric saved but no ID was assigned: #{saved_metric.name}")
        raise "Failed to assign ID to metric"
      end

      # Cache the metric
      @cache_port.cache_metric(saved_metric)

      Rails.logger.debug { "Created metric: #{saved_metric.id} (#{saved_metric.name})" }

      saved_metric
    end

    # NOTE: The following methods are no longer used since aggregation is now handled by
    # the background MetricAggregationJob, but we'll keep them here for reference

    # def should_update_aggregates?(metric)
    #   # Check if this metric should trigger aggregate updates
    #   # For example, metrics with .total in the name
    #   metric.name.include?(".total")
    # end
    #
    # def update_aggregates(metric)
    #   # Extract the base metric name (e.g., "github.push" from "github.push.total")
    #   base_parts = metric.name.split(".")
    #   return if base_parts.size < 2
    #
    #   # Get the base metric name without the counter type
    #   base_name = base_parts[0..1].join(".")
    #
    #   # Extract time periods for aggregation
    #   time_now = Time.now
    #   time_dimensions = {
    #     day: time_now.strftime("%Y-%m-%d"),
    #     month: time_now.strftime("%Y-%m"),
    #     year: time_now.strftime("%Y")
    #   }
    #
    #   # Update time-based aggregates for this metric
    #   update_time_aggregate(metric, "#{base_name}.daily", time_dimensions[:day])
    #   update_time_aggregate(metric, "#{base_name}.monthly", time_dimensions[:month])
    #   update_time_aggregate(metric, "#{base_name}.yearly", time_dimensions[:year])
    # end
    #
    # def update_time_aggregate(metric, aggregate_name, time_period)
    #   # Skip if storage port doesn't support aggregate operations
    #   return unless @storage_port.respond_to?(:find_aggregate_metric) &&
    #                 @storage_port.respond_to?(:update_metric)
    #
    #   # Extract key dimensions to include in the aggregate
    #   # This keeps aggregates grouped by important dimensions while filtering out details
    #   aggregate_dimensions = extract_aggregate_dimensions(metric).merge(
    #     time_period: time_period
    #   )
    #
    #   begin
    #     # Try to find an existing aggregate
    #     aggregate = @storage_port.find_aggregate_metric(
    #       aggregate_name,
    #       aggregate_dimensions
    #     )
    #
    #     if aggregate
    #       # Update existing aggregate
    #       updated_aggregate = aggregate.with_value(aggregate.value + metric.value)
    #       @storage_port.update_metric(updated_aggregate)
    #
    #       Rails.logger.debug { "Updated aggregate metric: #{aggregate_name} (#{time_period})" }
    #     else
    #       # Create new aggregate
    #       new_aggregate = Domain::Metric.new(
    #         name: aggregate_name,
    #         value: metric.value,
    #         source: metric.source,
    #         dimensions: aggregate_dimensions,
    #         timestamp: Time.now
    #       )
    #       @storage_port.save_metric(new_aggregate)
    #
    #       Rails.logger.debug { "Created new aggregate metric: #{aggregate_name} (#{time_period})" }
    #     end
    #   rescue StandardError => e
    #     # Log error but don't fail the entire operation
    #     Rails.logger.error { "Error updating aggregate #{aggregate_name}: #{e.message}" }
    #   end
    # end
    #
    # def extract_aggregate_dimensions(metric)
    #   # Extract important dimensions that should be included in aggregates
    #   # Filter out dimensions that are too specific
    #   metric.dimensions.select do |k, _|
    #     ["repository", "organization", "project", "provider", "source"].include?(k.to_s)
    #   end
    # end
  end
end
