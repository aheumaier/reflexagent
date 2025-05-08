# frozen_string_literal: true

module UseCases
  # CalculateMetrics is responsible for generating metrics from events
  # It uses MetricClassifier to determine which metrics to create for each event
  class CalculateMetrics
    def initialize(storage_port:, cache_port:, metric_classifier:, dimension_extractor: nil, team_repository_port: nil)
      @storage_port = storage_port
      @cache_port = cache_port
      @metric_classifier = metric_classifier
      @dimension_extractor = dimension_extractor
      @team_repository_port = team_repository_port
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

      # Ensure all metrics have repository dimensions if available
      ensure_repository_dimensions(classification[:metrics], event)

      # Create and save each metric
      saved_metrics = process_metrics(classification[:metrics], event)

      Rails.logger.debug { "Created #{saved_metrics.size} metrics from event: #{event.id}" }

      # If only one metric was created, return it for backward compatibility
      # Otherwise, return the array of metrics
      saved_metrics.size == 1 ? saved_metrics.first : saved_metrics
    end

    private

    # Ensure that all metrics have repository dimensions when available
    # @param metrics [Array<Hash>] The metrics to process
    # @param event [Domain::Event] The source event
    def ensure_repository_dimensions(metrics, event)
      # First, try to extract repository info from metrics
      repo_name = extract_repository_from_metrics(metrics)

      # If not found in metrics, try to extract from event directly
      repo_name = extract_repository_from_event(event) if repo_name.nil? || repo_name == "unknown"

      # If we found a repository name, ensure all metrics have it
      return unless repo_name.present? && repo_name != "unknown"

      # Try to register the repository and team if possible
      register_repository(repo_name, event) if @team_repository_port.present?

      # Add/update repository dimension in all metrics
      metrics.each do |metric|
        metric[:dimensions] ||= {}

        # Only add repository dimension if not already present
        metric[:dimensions][:repository] = repo_name unless metric[:dimensions][:repository].present?

        # Extract organization if available and not already present
        if @dimension_extractor && !metric[:dimensions][:organization].present?
          org_name = @dimension_extractor.extract_org_from_repo(repo_name)
          metric[:dimensions][:organization] = org_name if org_name.present?
        end
      end
    end

    # Register the repository and team based on the repository name
    # @param repo_name [String] The repository name (e.g., "org/repo")
    # @param event [Domain::Event] The source event for context
    def register_repository(repo_name, event)
      # Extract organization name from repository
      org_name = @dimension_extractor&.extract_org_from_repo(repo_name)

      # Find or create the team
      if org_name.present?
        find_or_create_team_use_case = UseCases::FindOrCreateTeam.new(
          team_repository_port: @team_repository_port,
          logger_port: Rails.logger
        )

        team = find_or_create_team_use_case.call(name: org_name)
        team_id = team&.id
      end

      # If no team found, use the default
      unless team_id
        default_team = ::Team.first
        team_id = default_team&.id || 1
      end

      # Check if repository already exists
      existing_repo = @team_repository_port.find_repository_by_name(repo_name)

      # If repository exists, respect its existing team assignment
      team_id = existing_repo.team_id if existing_repo&.team_id.present?

      # Extract URL from event if possible
      url = nil
      url = event.data[:repository][:html_url] if event.data.is_a?(Hash) && event.data[:repository].is_a?(Hash)

      # Register the repository
      register_repository_use_case = UseCases::RegisterRepository.new(
        team_repository_port: @team_repository_port,
        logger_port: Rails.logger
      )

      register_repository_use_case.call(
        name: repo_name,
        url: url,
        provider: "github",
        team_id: team_id
      )
    rescue StandardError => e
      Rails.logger.error { "Error registering repository/team in calculate_metrics: #{e.message}" }
      # Continue processing even if registration fails
    end

    # Extract repository name from event data
    # @param event [Domain::Event] The event to extract from
    # @return [String, nil] The repository name, or nil if not found
    def extract_repository_from_event(event)
      return nil unless event.data.is_a?(Hash)

      if event.data[:repository].is_a?(Hash) && event.data[:repository][:full_name].present?
        event.data[:repository][:full_name]
      else
        nil
      end
    end

    # Process and save metrics
    def process_metrics(metric_defs, event)
      metric_defs.map do |metric_def|
        # Create a new metric instance
        metric = Domain::Metric.new(
          name: metric_def[:name],
          value: metric_def[:value],
          source: event.source,
          dimensions: metric_def[:dimensions] || {},
          timestamp: event.timestamp
        )

        # Save the metric
        @storage_port.save_metric(metric)

        # Cache the metric
        @cache_port.write("metric:#{metric.id}", metric, expires_in: 24.hours)

        metric
      end
    end

    # Enhance GitHub push events with additional commit-related metrics
    def enhance_with_commit_metrics(event, metrics)
      # Extract repository name from existing metrics
      repository = extract_repository_from_metrics(metrics)

      # Get additionalcommit-related metrics
      additional_metrics = []

      # Extract file changes if they exist in the event data
      if event.data[:commits]
        file_changes = @dimension_extractor.extract_file_changes(event)

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
