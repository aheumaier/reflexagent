# frozen_string_literal: true

class AlertService
  def initialize(storage_port:)
    @storage_port = storage_port
  end

  # Get recent alerts
  def recent_alerts(limit: 5, severity: nil, days: nil)
    filters = { latest_first: true, limit: limit }
    filters[:severity] = severity if severity
    filters[:start_time] = days.days.ago if days

    # First, try to get real alerts from the storage port
    alerts = @storage_port.list_alerts(filters)

    # If no real alerts, try to create some sample alerts first
    if alerts.nil? || alerts.empty?
      Rails.logger.info("No alerts found, checking if we need to generate samples")

      # Check if there are any alerts in the database
      if DomainAlert.count.zero?
        Rails.logger.info("Creating sample alerts for demonstration")
        DomainAlert.create_sample_alerts(limit)

        # Try again after creating samples
        alerts = @storage_port.list_alerts(filters)
      end
    end

    alerts
  end

  # Get active alerts count by severity
  def alert_counts_by_severity
    alerts = @storage_port.list_alerts(status: "active")

    # Group by severity
    alerts.group_by(&:severity).transform_values(&:count)
  end

  # Get alert trends
  def alert_trends(days: 7)
    start_time = days.days.ago

    alerts = @storage_port.list_alerts(
      start_time: start_time,
      include_resolved: true
    )

    # Group by day and severity
    alerts.group_by do |alert|
      alert.timestamp.strftime("%Y-%m-%d")
    end.transform_values do |daily_alerts|
      daily_alerts.group_by(&:severity).transform_values(&:count)
    end
  end
end
