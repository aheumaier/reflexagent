# frozen_string_literal: true

class MetricAggregationJob
  include Sidekiq::Job

  sidekiq_options queue: "metric_aggregation", retry: 3

  def perform(time_period = "5min")
    Rails.logger.info("Starting metric aggregation for period: #{time_period}")

    # Get timestamp range for this aggregation period
    end_time = Time.current
    start_time = case time_period
                 when "5min"
                   5.minutes.ago
                 when "hourly"
                   1.hour.ago
                 when "daily"
                   1.day.ago
                 when "monthly"
                   1.month.ago
                 when "yearly"
                   1.year.ago
                 else
                   5.minutes.ago
                 end

    # Process metrics in this time window
    metrics_count = process_metrics_in_window(start_time, end_time, time_period)

    # Only generate DORA metrics for daily or longer periods
    if ["daily", "monthly", "yearly"].include?(time_period)
      Rails.logger.info("Generating DORA metrics for period: #{time_period}")
      dora_metrics_count = process_dora_metrics(time_period)
      Rails.logger.info("Generated #{dora_metrics_count} DORA metrics")
    end

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

    # Create service instances
    dora_service = ServiceFactory.create_dora_service

    # Calculate different time periods to generate DORA metrics for
    # Regardless of aggregation schedule, we want metrics for standard dashboard filter periods
    standard_periods = [7, 30, 90]

    Rails.logger.info("Calculating DORA metrics for standard periods: #{standard_periods.join(', ')} days")

    # Track how many metrics we create
    dora_metrics_count = 0

    # Process each standard time period
    standard_periods.each do |days|
      # Get each DORA metric for this period
      deployment_frequency = dora_service.deployment_frequency(days)
      lead_time = dora_service.lead_time_for_changes(days)
      time_to_restore = dora_service.time_to_restore_service(days)
      change_failure_rate = dora_service.change_failure_rate(days)

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
      # Group by base name (e.g., github.push from github.push.total)
      base_parts = metric.name.split(".")
      base_name = base_parts.size >= 2 ? base_parts[0..1].join(".") : metric.name

      # Include source and any other important dimensions in the grouping
      [base_name, metric.source, metric.dimensions["repository"]]
    end
  end

  def update_aggregates_for_group(key, metrics, time_period)
    base_name, source, repository = key
    metric_repository = DependencyContainer.resolve(:metric_repository)

    # Calculate total for this group
    total_value = metrics.sum(&:value)

    # Build dimensions
    dimensions = {
      source: source,
      time_period: formatted_time_period(time_period)
    }
    dimensions[:repository] = repository if repository

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
