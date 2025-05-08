# frozen_string_literal: true

require_relative "../core/use_cases/calculate_deployment_frequency"
require_relative "../core/use_cases/calculate_lead_time"
require_relative "../core/use_cases/calculate_time_to_restore"
require_relative "../core/use_cases/calculate_change_failure_rate"

class MetricAggregationJob
  include Sidekiq::Job

  sidekiq_options queue: "metric_aggregation", retry: 3

  def perform(time_period = "daily")
    Rails.logger.info("Starting metric aggregation for period: #{time_period}")

    # Get timestamp range for this aggregation period
    end_time = Time.current
    start_time = case time_period
                 when "hourly"
                   1.hour.ago
                 when "daily"
                   1.day.ago
                 when "monthly"
                   1.month.ago
                 when "yearly"
                   1.year.ago
                 else
                   1.day.ago
                 end

    # Process metrics in this time window
    metrics_count = process_metrics_in_window(start_time, end_time, time_period)

    # Only generate DORA metrics for daily or longer periods
    dora_metrics_count = process_dora_metrics(time_period) if ["daily", "monthly", "yearly"].include?(time_period)

    Rails.logger.info("Completed metric aggregation for period: #{time_period}, processed #{metrics_count} metrics")
  rescue StandardError => e
    Rails.logger.error("Error in MetricAggregationJob: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise
  end

  private

  def process_metrics_in_window(start_time, end_time, time_period)
    metric_repository = DependencyContainer.resolve(:metric_repository)

    # Get metrics that need aggregation (with .total suffix)
    metrics = metric_repository.list_metrics(
      start_time: start_time,
      end_time: end_time,
      name_pattern: "%.total"
    )

    # Also get commit-related metrics that need aggregation
    # These metrics are needed by the CommitMetricsController
    additional_metrics = []

    # github.push.commits - for commit volume metrics
    commit_metrics = metric_repository.list_metrics(
      start_time: start_time,
      end_time: end_time,
      name: "github.push.commits"
    )
    additional_metrics.concat(commit_metrics)

    # github.push.directory_changes - for directory hotspots
    directory_metrics = metric_repository.list_metrics(
      start_time: start_time,
      end_time: end_time,
      name: "github.push.directory_changes"
    )
    additional_metrics.concat(directory_metrics)

    # github.push.filetype_changes - for file extension hotspots
    filetype_metrics = metric_repository.list_metrics(
      start_time: start_time,
      end_time: end_time,
      name: "github.push.filetype_changes"
    )
    additional_metrics.concat(filetype_metrics)

    # github.push.commit_type - for commit types
    commit_type_metrics = metric_repository.list_metrics(
      start_time: start_time,
      end_time: end_time,
      name: "github.push.commit_type"
    )
    additional_metrics.concat(commit_type_metrics)

    # github.push.breaking_change - for breaking changes
    breaking_change_metrics = metric_repository.list_metrics(
      start_time: start_time,
      end_time: end_time,
      name: "github.push.breaking_change"
    )
    additional_metrics.concat(breaking_change_metrics)

    # github.push.code_additions and github.push.code_deletions - for code churn
    code_additions_metrics = metric_repository.list_metrics(
      start_time: start_time,
      end_time: end_time,
      name: "github.push.code_additions"
    )
    additional_metrics.concat(code_additions_metrics)

    code_deletions_metrics = metric_repository.list_metrics(
      start_time: start_time,
      end_time: end_time,
      name: "github.push.code_deletions"
    )
    additional_metrics.concat(code_deletions_metrics)

    # Combine all metrics that need aggregation
    metrics.concat(additional_metrics)

    Rails.logger.info("Found #{metrics.size} metrics to aggregate for period: #{time_period}")
    return 0 if metrics.empty?

    # Group metrics by source and name for efficient aggregation
    grouped_metrics = group_metrics_for_aggregation(metrics)

    # Process each group in a single transaction
    grouped_metrics.each do |key, metrics_group|
      update_aggregates_for_group(key, metrics_group, time_period)
    end

    metrics.size
  end

  def process_dora_metrics(time_period)
    metric_repository = DependencyContainer.resolve(:metric_repository)

    # Initialize use cases for DORA metrics
    calculate_deployment_frequency = UseCases::CalculateDeploymentFrequency.new(
      storage_port: metric_repository,
      logger_port: Rails.logger
    )

    calculate_lead_time = UseCases::CalculateLeadTime.new(
      storage_port: metric_repository,
      logger_port: Rails.logger
    )

    calculate_time_to_restore = UseCases::CalculateTimeToRestore.new(
      storage_port: metric_repository,
      logger_port: Rails.logger
    )

    calculate_change_failure_rate = UseCases::CalculateChangeFailureRate.new(
      storage_port: metric_repository,
      logger_port: Rails.logger
    )

    # Calculate different time periods to generate DORA metrics for
    # Regardless of aggregation schedule, we want metrics for standard dashboard filter periods
    standard_periods = [7, 30, 90]

    Rails.logger.info("Calculating DORA metrics for standard periods: #{standard_periods.join(', ')} days")

    # Track how many metrics we create
    dora_metrics_count = 0

    # Process each standard time period
    standard_periods.each do |days|
      # Get each DORA metric for this period
      deployment_frequency = calculate_deployment_frequency.call(time_period: days)
      lead_time = calculate_lead_time.call(time_period: days)
      time_to_restore = calculate_time_to_restore.call(time_period: days)
      change_failure_rate = calculate_change_failure_rate.call(time_period: days)

      # Record current timestamp for consistency across all metrics
      timestamp = Time.current
      time_period_str = timestamp.strftime("%Y-%m-%d")

      # Create a metric for deployment frequency
      metric = Domain::Metric.new(
        name: "dora.deployment_frequency",
        value: deployment_frequency[:value],
        source: "reflexagent.dora",
        timestamp: timestamp,
        dimensions: {
          "period_days" => days.to_s,
          "rating" => deployment_frequency[:rating],
          "time_period" => time_period_str,
          "days_with_deployments" => deployment_frequency[:days_with_deployments].to_s,
          "total_deployments" => deployment_frequency[:total_deployments].to_s,
          "calculation_timestamp" => timestamp.iso8601
        }
      )

      metric_repository.save_metric(metric)
      dora_metrics_count += 1

      # Create a metric for lead time
      metric = Domain::Metric.new(
        name: "dora.lead_time",
        value: lead_time[:value],
        source: "reflexagent.dora",
        timestamp: timestamp,
        dimensions: {
          "period_days" => days.to_s,
          "rating" => lead_time[:rating],
          "time_period" => time_period_str,
          "sample_size" => lead_time[:sample_size].to_s,
          "calculation_timestamp" => timestamp.iso8601
        }
      )

      metric_repository.save_metric(metric)
      dora_metrics_count += 1

      # Create a metric for time to restore
      metric = Domain::Metric.new(
        name: "dora.time_to_restore",
        value: time_to_restore[:value],
        source: "reflexagent.dora",
        timestamp: timestamp,
        dimensions: {
          "period_days" => days.to_s,
          "rating" => time_to_restore[:rating],
          "time_period" => time_period_str,
          "sample_size" => time_to_restore[:sample_size].to_s,
          "calculation_timestamp" => timestamp.iso8601
        }
      )

      metric_repository.save_metric(metric)
      dora_metrics_count += 1

      # Create a metric for change failure rate
      metric = Domain::Metric.new(
        name: "dora.change_failure_rate",
        value: change_failure_rate[:value],
        source: "reflexagent.dora",
        timestamp: timestamp,
        dimensions: {
          "period_days" => days.to_s,
          "rating" => change_failure_rate[:rating],
          "time_period" => time_period_str,
          "failures" => change_failure_rate[:failures].to_s,
          "deployments" => change_failure_rate[:deployments].to_s,
          "calculation_timestamp" => timestamp.iso8601
        }
      )

      metric_repository.save_metric(metric)
      dora_metrics_count += 1
    end

    Rails.logger.info("Created #{dora_metrics_count} DORA metrics for period: #{time_period}")
  end

  def group_metrics_for_aggregation(metrics)
    metrics.group_by do |metric|
      # For metrics that don't follow the .total pattern, preserve the full name
      if ["github.push.commits",
          "github.push.directory_changes",
          "github.push.filetype_changes",
          "github.push.commit_type",
          "github.push.breaking_change",
          "github.push.code_additions",
          "github.push.code_deletions"].include?(metric.name)
        base_name = metric.name
      else
        # Group by base name (e.g., github.push from github.push.total)
        base_parts = metric.name.split(".")
        base_name = base_parts.size >= 2 ? base_parts[0..1].join(".") : metric.name
      end

      # Include relevant dimensions in the grouping
      # For metrics with specialized dimensions like directory/filetype/type, include those in the grouping
      additional_grouping = case metric.name
                            when "github.push.directory_changes"
                              metric.dimensions["directory"]
                            when "github.push.filetype_changes"
                              metric.dimensions["filetype"]
                            when "github.push.commit_type"
                              metric.dimensions["type"]
                            else
                              nil
                            end

      # Include source and any other important dimensions in the grouping
      [base_name, metric.source, metric.dimensions["repository"], additional_grouping]
    end
  end

  def update_aggregates_for_group(key, metrics, time_period)
    base_name, source, repository, additional_grouping = key
    metric_repository = DependencyContainer.resolve(:metric_repository)

    # Calculate total for this group
    total_value = metrics.sum(&:value)

    # Build dimensions
    dimensions = {
      source: source,
      time_period: formatted_time_period(time_period)
    }
    dimensions[:repository] = repository if repository

    # Add the appropriate dimension name based on the metric type
    if additional_grouping
      case base_name
      when "github.push.directory_changes"
        dimensions[:directory] = additional_grouping
      when "github.push.filetype_changes"
        dimensions[:filetype] = additional_grouping
      when "github.push.commit_type"
        dimensions[:type] = additional_grouping
      else
        dimensions[:additional_grouping] = additional_grouping
      end
    end

    # Determine aggregate name based on time period
    aggregate_name = "#{base_name}.#{period_suffix(time_period)}"

    Rails.logger.debug { "Updating aggregate: #{aggregate_name} with value: #{total_value}" }

    # Update or create the aggregate in a transaction
    ActiveRecord::Base.transaction do
      aggregate = metric_repository.find_aggregate_metric(aggregate_name, dimensions)

      if aggregate
        # Update existing aggregate
        updated_aggregate = aggregate.with_value(total_value)
        metric_repository.update_metric(updated_aggregate)
        Rails.logger.debug { "Updated existing aggregate: #{aggregate_name} (#{dimensions[:time_period]})" }
      else
        # Create new aggregate
        new_aggregate = Domain::Metric.new(
          name: aggregate_name,
          value: total_value,
          source: source,
          dimensions: dimensions,
          timestamp: Time.current
        )
        saved_aggregate = metric_repository.save_metric(new_aggregate)
        Rails.logger.debug do
          "Created new aggregate: #{aggregate_name} (#{dimensions[:time_period]}) with ID: #{saved_aggregate.id}"
        end
      end
    end
  end

  def formatted_time_period(time_period)
    case time_period
    when "5min"
      # Round to nearest 5-minute interval
      time = Time.current
      rounded_min = (time.min / 5) * 5
      time.change(min: rounded_min).strftime("%Y-%m-%d-%H-%M")
    when "hourly"
      Time.current.strftime("%Y-%m-%d-%H")
    when "daily"
      Time.current.strftime("%Y-%m-%d")
    when "monthly"
      Time.current.strftime("%Y-%m")
    when "yearly"
      Time.current.strftime("%Y")
    else
      Time.current.strftime("%Y-%m-%d-%H-%M")
    end
  end

  def period_suffix(time_period)
    case time_period
    when "5min" then "5min"
    when "hourly" then "hourly"
    when "daily" then "daily"
    when "monthly" then "monthly"
    when "yearly" then "yearly"
    else "5min"
    end
  end
end
