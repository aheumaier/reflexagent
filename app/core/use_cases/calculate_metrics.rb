# frozen_string_literal: true

module UseCases
  # CalculateMetrics is responsible for generating metrics from events
  # It uses MetricClassifier to determine which metrics to create for each event
  class CalculateMetrics
    def initialize(storage_port:, cache_port:, metric_classifier:, dimension_extractor: nil)
      @storage_port = storage_port
      @cache_port = cache_port
      @metric_classifier = metric_classifier
      @dimension_extractor = dimension_extractor
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

      # Process additional commit-related metrics if this is a GitHub push event
      if event.name == "github.push" && @dimension_extractor
        enhanced_metrics = enhance_with_commit_metrics(event, classification[:metrics])
        classification[:metrics].concat(enhanced_metrics)
      end

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

    # New method to generate additional metrics from commit details
    def enhance_with_commit_metrics(event, existing_metrics)
      return [] unless @dimension_extractor && event.data[:commits]

      additional_metrics = []
      repository = extract_repository_from_metrics(existing_metrics)

      # Don't duplicate work if these metrics are already included by the classifier
      return [] if metrics_contain_conventional_commit_data?(existing_metrics)

      # Extract conventional commit data
      event.data[:commits].each do |commit|
        commit_parts = @dimension_extractor.extract_conventional_commit_parts(commit)

        # Only process conventional commits
        next unless commit_parts[:commit_conventional]

        # Add commit type metric if not already tracked
        additional_metrics << {
          name: "github.commit.type",
          value: 1,
          dimensions: {
            repository: repository,
            commit_type: commit_parts[:commit_type],
            commit_scope: commit_parts[:commit_scope] || "none"
          }
        }

        # Track breaking changes separately
        next unless commit_parts[:commit_breaking]

        additional_metrics << {
          name: "github.commit.breaking_change",
          value: 1,
          dimensions: {
            repository: repository,
            commit_type: commit_parts[:commit_type],
            commit_scope: commit_parts[:commit_scope] || "none",
            author: extract_commit_author(commit, event)
          }
        }
      end

      # Get file changes
      file_changes = @dimension_extractor.extract_file_changes(event)

      # Only add if we have meaningful results
      if file_changes[:files_added] > 0 || file_changes[:files_modified] > 0 || file_changes[:files_removed] > 0
        # Add directory hotspot metrics
        if file_changes[:directory_hotspots].present?
          file_changes[:directory_hotspots].each do |dir, count|
            additional_metrics << {
              name: "github.commit.directory_change",
              value: count,
              dimensions: {
                repository: repository,
                directory: dir
              }
            }
          end
        end

        # Add file extension metrics
        if file_changes[:extension_hotspots].present?
          file_changes[:extension_hotspots].each do |ext, count|
            additional_metrics << {
              name: "github.commit.file_extension",
              value: count,
              dimensions: {
                repository: repository,
                extension: ext
              }
            }
          end
        end
      end

      # Extract code volume metrics
      code_volume = @dimension_extractor.extract_code_volume(event)

      if code_volume[:code_additions] > 0 || code_volume[:code_deletions] > 0
        additional_metrics << {
          name: "github.commit.code_volume",
          value: code_volume[:code_churn],
          dimensions: {
            repository: repository,
            additions: code_volume[:code_additions],
            deletions: code_volume[:code_deletions]
          }
        }
      end

      additional_metrics
    end

    def extract_repository_from_metrics(metrics)
      # Find the repository dimension in any of the metrics
      metrics.each do |metric|
        return metric[:dimensions][:repository] if metric[:dimensions] && metric[:dimensions][:repository]
      end
      "unknown"
    end

    def extract_commit_author(commit, event)
      # Try to extract author from commit
      return commit[:author][:name] if commit[:author] && commit[:author][:name]
      return commit[:author][:login] if commit[:author] && commit[:author][:login]

      # Fall back to event data
      return event.data[:sender][:login] if event.data[:sender] && event.data[:sender][:login]
      return event.data[:pusher][:name] if event.data[:pusher] && event.data[:pusher][:name]

      "unknown"
    end

    def metrics_contain_conventional_commit_data?(metrics)
      # Check if any metrics already track conventional commit data
      metrics.any? do |m|
        ["github.push.commit_type", "github.push.breaking_change", "github.commit.type",
         "github.commit.breaking_change"].include?(m[:name])
      end
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
