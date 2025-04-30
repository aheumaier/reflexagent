class DomainAlert < ApplicationRecord
  validates :name, presence: true
  validates :severity, presence: true, inclusion: { in: %w[info warning critical] }
  validates :metric_data, presence: true
  validates :threshold, presence: true
  validates :status, presence: true, inclusion: { in: %w[active acknowledged resolved] }
  validates :timestamp, presence: true

  scope :active, -> { where(status: 'active') }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :critical, -> { where(severity: 'critical') }
  scope :warning, -> { where(severity: 'warning') }
  scope :info, -> { where(severity: 'info') }
  scope :recent, ->(limit = 10) { order(timestamp: :desc).limit(limit) }

  def to_domain_model
    metric = Core::Domain::Metric.new(
      id: metric_data['id'],
      name: metric_data['metric_name'],
      value: metric_data['metric_value'],
      source: metric_data['source'],
      dimensions: metric_data['dimensions'] || {},
      timestamp: metric_data['timestamp'] ? Time.parse(metric_data['timestamp']) : Time.now
    )

    Core::Domain::Alert.new(
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
      'id' => alert.metric.id,
      'metric_name' => alert.metric.name,
      'metric_value' => alert.metric.value,
      'source' => alert.metric.source,
      'dimensions' => alert.metric.dimensions,
      'timestamp' => alert.metric.timestamp.iso8601
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
