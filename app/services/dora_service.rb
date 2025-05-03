# frozen_string_literal: true

# Service for calculating DORA (DevOps Research and Assessment) metrics
# https://cloud.google.com/blog/products/devops-sre/using-the-four-keys-to-measure-your-devops-performance
class DoraService
  def initialize(storage_port:)
    @storage_port = storage_port
  end

  # Calculate deployment frequency (deployments per day)
  def deployment_frequency(days = 30)
    start_time = days.days.ago

    Rails.logger.info("Calculating deployment frequency for past #{days} days")

    deployments = @storage_port.list_metrics(
      name: "ci.deploy.completed",
      start_time: start_time
    )

    Rails.logger.info("Found #{deployments.count} total deployments")

    # Group by day
    deployments_by_day = deployments.group_by do |metric|
      metric.timestamp.strftime("%Y-%m-%d")
    end

    # Debug info about deployments by day
    if deployments_by_day.any?
      Rails.logger.info("Deployment dates: #{deployments_by_day.keys.sort.join(', ')}")
    else
      Rails.logger.warn("No deployments found in the specified time period")
    end

    # Count days with at least one deployment
    days_with_deployments = deployments_by_day.keys.size

    Rails.logger.info("Days with at least one deployment: #{days_with_deployments}")

    # Calculate frequency
    if days_with_deployments > 0
      frequency = (days_with_deployments.to_f / days).round(2)
      rating = deployment_frequency_rating(frequency)

      Rails.logger.info("Deployment frequency: #{frequency} per day, Rating: #{rating}")

      {
        value: frequency,
        rating: rating,
        days_with_deployments: days_with_deployments,
        total_days: days,
        total_deployments: deployments.count
      }
    else
      Rails.logger.warn("No deployments found - returning 'low' rating")

      {
        value: 0,
        rating: "low",
        days_with_deployments: 0,
        total_days: days,
        total_deployments: 0
      }
    end
  end

  # Calculate lead time for changes (time from commit to production)
  def lead_time_for_changes(days = 30)
    start_time = days.days.ago

    # Get lead time metrics
    lead_time_metrics = @storage_port.list_metrics(
      name: "ci.lead_time",
      start_time: start_time
    )

    if lead_time_metrics.any?
      avg_lead_time_hours = lead_time_metrics.sum(&:value) / lead_time_metrics.size / 3600

      {
        value: avg_lead_time_hours.round(2),
        rating: lead_time_rating(avg_lead_time_hours),
        sample_size: lead_time_metrics.size
      }
    else
      { value: 0, rating: "unknown", sample_size: 0 }
    end
  end

  # Calculate time to restore service (MTTR)
  def time_to_restore_service(days = 30)
    start_time = days.days.ago

    # Get incident resolution metrics
    restoration_metrics = @storage_port.list_metrics(
      name: "incident.resolution_time",
      start_time: start_time
    )

    if restoration_metrics.any?
      avg_restore_time_hours = restoration_metrics.sum(&:value) / restoration_metrics.size / 3600

      {
        value: avg_restore_time_hours.round(2),
        rating: restore_time_rating(avg_restore_time_hours),
        sample_size: restoration_metrics.size
      }
    else
      { value: 0, rating: "unknown", sample_size: 0 }
    end
  end

  # Calculate change failure rate (% of deployments causing incidents)
  def change_failure_rate(days = 30)
    start_time = days.days.ago

    # Get deployment metrics
    deployments = @storage_port.list_metrics(
      name: "ci.deploy.completed",
      start_time: start_time
    )

    # Get failed deployment metrics
    failed_deployments = @storage_port.list_metrics(
      name: "ci.deploy.incident",
      start_time: start_time
    )

    total_deployments = deployments.sum(&:value)
    total_failures = failed_deployments.sum(&:value)

    if total_deployments > 0
      failure_rate = (total_failures.to_f / total_deployments * 100).round(2)

      {
        value: failure_rate,
        rating: failure_rate_rating(failure_rate),
        failures: total_failures,
        deployments: total_deployments
      }
    else
      { value: 0, rating: "unknown", failures: 0, deployments: 0 }
    end
  end

  private

  # Rating systems based on DORA research

  def deployment_frequency_rating(deployments_per_day)
    if deployments_per_day >= 1
      "elite"       # Multiple deploys per day
    elsif deployments_per_day >= 0.14
      "high"        # Between once per day and once per week
    elsif deployments_per_day >= 0.03
      "medium"      # Between once per week and once per month
    else
      "low"         # Less than once per month
    end
  end

  def lead_time_rating(hours)
    if hours <= 24
      "elite"       # Less than one day
    elsif hours <= 168
      "high"        # Less than one week
    elsif hours <= 730
      "medium"      # Less than one month
    else
      "low"         # More than one month
    end
  end

  def restore_time_rating(hours)
    if hours < 1
      "elite"       # Less than one hour
    elsif hours < 24
      "high"        # Less than one day
    elsif hours < 168
      "medium"      # Less than one week
    else
      "low"         # More than one week
    end
  end

  def failure_rate_rating(percentage)
    if percentage <= 15
      "elite"       # 0-15%
    elsif percentage <= 30
      "high"        # 16-30%
    elsif percentage <= 45
      "medium"      # 31-45%
    else
      "low"         # 46-100%
    end
  end
end
