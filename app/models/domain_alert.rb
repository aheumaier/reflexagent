class DomainAlert < ApplicationRecord
  validates :name, presence: true
  validates :severity, presence: true, inclusion: { in: ["info", "warning", "critical"] }
  validates :metric_data, presence: true
  validates :threshold, presence: true
  validates :status, presence: true, inclusion: { in: ["active", "acknowledged", "resolved"] }
  validates :timestamp, presence: true

  scope :active, -> { where(status: "active") }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :critical, -> { where(severity: "critical") }
  scope :warning, -> { where(severity: "warning") }
  scope :info, -> { where(severity: "info") }
  scope :recent, ->(limit = 10) { order(timestamp: :desc).limit(limit) }

  # Create sample alerts for testing and demonstration
  def self.create_sample_alerts(count = 5)
    return if count < 1

    # Sample alert data
    alert_types = [
      "High CPU Usage",
      "Memory Leak Detected",
      "Slow Database Query",
      "API Rate Limit Exceeded",
      "Disk Space Warning",
      "Network Latency Spike",
      "Cache Miss Rate High"
    ]

    severities = ["info", "warning", "critical"]
    statuses = ["active", "acknowledged", "resolved"]
    sources = ["monitoring", "system", "application"]

    # Create sample alerts
    count.times do |i|
      # Create sample metric data
      metric_data = {
        "id" => "sample_#{i}",
        "metric_name" => "system.#{['cpu', 'memory', 'disk', 'network'].sample}",
        "metric_value" => rand(50..100),
        "source" => sources.sample,
        "dimensions" => {
          "host" => "server-#{rand(1..5)}",
          "environment" => ["production", "staging"].sample
        },
        "timestamp" => (Time.now - rand(1..48).hours).iso8601
      }

      # Create the alert
      create!(
        name: "#{alert_types.sample} #{i + 1}",
        severity: severities.sample,
        metric_data: metric_data,
        threshold: rand(50..95),
        status: statuses.sample,
        timestamp: Time.now - rand(1..72).hours
      )
    end

    Rails.logger.info "Created #{count} sample alerts"
  end

  def to_domain_model
    metric = Domain::Metric.new(
      id: metric_data["id"],
      name: metric_data["metric_name"],
      value: metric_data["metric_value"],
      source: metric_data["source"],
      dimensions: metric_data["dimensions"] || {},
      timestamp: metric_data["timestamp"] ? Time.parse(metric_data["timestamp"]) : Time.now
    )

    Domain::Alert.new(
      id: id.to_s,
      name: name,
      severity: severity.to_sym,
      metric: metric,
      threshold: threshold,
      timestamp: timestamp,
      status: status.to_sym
    )
  end

  def self.from_domain_model(alert)
    metric_data = {
      "id" => alert.metric.id,
      "metric_name" => alert.metric.name,
      "metric_value" => alert.metric.value,
      "source" => alert.metric.source,
      "dimensions" => alert.metric.dimensions,
      "timestamp" => alert.metric.timestamp.iso8601
    }

    domain_alert = find_by(id: alert.id) if alert.id.present?

    attributes = {
      name: alert.name,
      severity: alert.severity.to_s,
      metric_data: metric_data,
      threshold: alert.threshold,
      status: alert.status.to_s,
      timestamp: alert.timestamp
    }

    if domain_alert
      domain_alert.update!(attributes)
      domain_alert
    else
      create!(attributes)
    end
  end
end
