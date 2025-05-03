# frozen_string_literal: true

class MetricsService
  def initialize(storage_port:, cache_port:)
    @storage_port = storage_port
    @cache_port = cache_port
  end

  # Get aggregate metrics with time period grouping
  def aggregate_metrics(metric_name, time_period = "daily", days = 7)
    start_time = days.days.ago

    metrics = @storage_port.list_metrics(
      name: metric_name,
      start_time: start_time,
      latest_first: true
    )

    # Group by time period
    metrics.group_by do |metric|
      case time_period
      when "daily"
        metric.timestamp.strftime("%Y-%m-%d")
      when "weekly"
        metric.timestamp.beginning_of_week.strftime("%Y-%m-%d")
      when "monthly"
        metric.timestamp.strftime("%Y-%m")
      else
        metric.timestamp.strftime("%Y-%m-%d")
      end
    end.transform_values do |metrics_for_period|
      metrics_for_period.sum(&:value)
    end
  end

  # Get top metrics by a specific dimension
  def top_metrics(metric_name, dimension:, limit: 5, days: 30)
    start_time = days.days.ago

    metrics = @storage_port.list_metrics(
      name: metric_name,
      start_time: start_time
    )

    # Group by the specified dimension
    grouped = metrics.group_by do |metric|
      metric.dimensions[dimension.to_s] || metric.dimensions[dimension.to_sym] || "unknown"
    end

    # Sum values and sort
    sorted = grouped.transform_values do |dimension_metrics|
      dimension_metrics.sum(&:value)
    end.sort_by { |_, value| -value }

    # Return top N results
    sorted.first(limit).to_h
  end

  # Calculate success rate for CI/CD operations
  def success_rate(metric_base_name, days = 30)
    start_time = days.days.ago

    success_metrics = @storage_port.list_metrics(
      name: "#{metric_base_name}.completed",
      start_time: start_time
    )

    total_metrics = @storage_port.list_metrics(
      name: "#{metric_base_name}.total",
      start_time: start_time
    )

    total_count = total_metrics.sum(&:value)
    success_count = success_metrics.sum(&:value)

    # Ensure we don't return more than 100%, which can happen if we have more
    # completed metrics than total metrics (data inconsistency)
    if total_count > 0
      rate = (success_count.to_f / total_count * 100).round(2)
      # Cap the success rate at 100%
      [rate, 100.0].min
    else
      0
    end
  end

  # Calculate average for a metric
  def average_metric(metric_name, days = 30)
    start_time = days.days.ago
    end_time = Time.now

    @storage_port.get_average(metric_name, start_time, end_time)
  end

  # Calculate team velocity (completed tasks per week)
  def team_velocity(weeks = 4)
    start_time = weeks.weeks.ago

    # Use direct query for task metrics because the repository's name_pattern doesn't work as expected
    task_metrics = []

    # Use the DomainMetric model directly with a SQL LIKE clause
    domain_metrics = DomainMetric.where("name LIKE 'task.%.total'")
                                 .where("recorded_at >= ?", start_time)
                                 .order(recorded_at: :desc)

    # Convert database records to domain models
    task_metrics = domain_metrics.map do |record|
      Domain::Metric.new(
        id: record.id.to_s,
        name: record.name,
        value: record.value,
        source: record.source,
        dimensions: record.dimensions || {},
        timestamp: record.recorded_at
      )
    end

    Rails.logger.info("Found #{task_metrics.size} task metrics for velocity calculation")

    # Group by week and calculate sums
    velocity_by_week = task_metrics.group_by do |metric|
      metric.timestamp.beginning_of_week.strftime("%Y-%m-%d")
    end.transform_values do |weekly_metrics|
      weekly_metrics.sum(&:value)
    end

    # Calculate average weekly velocity
    values = velocity_by_week.values

    # If we have data, calculate the average, otherwise return 0
    if values.any?
      average_velocity = (values.sum.to_f / values.size).round(2)
      Rails.logger.info("Calculated average velocity: #{average_velocity} tasks per week")
      average_velocity
    else
      Rails.logger.warn("No task metrics found for velocity calculation")
      0
    end
  end
end
