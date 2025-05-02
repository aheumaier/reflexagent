# frozen_string_literal: true

module Domain
  class Alert
    attr_reader :id, :name, :severity, :metric, :threshold, :timestamp, :status

    SEVERITIES = [:info, :warning, :critical].freeze
    STATUSES = [:active, :acknowledged, :resolved].freeze

    def initialize(name:, severity:, metric:, threshold:, id: nil, timestamp: Time.now, status: :active)
      @id = id
      @name = name
      @severity = severity
      @metric = metric
      @threshold = threshold
      @timestamp = timestamp
      @status = status
      validate!
    end

    def message
      "#{name} - #{metric.name} exceeded threshold of #{threshold}"
    end

    def details
      {
        metric_name: metric.name,
        metric_value: metric.value,
        threshold: threshold,
        source: metric.source,
        dimensions: metric.dimensions
      }
    end

    def created_at
      timestamp
    end

    # Validation methods
    def valid?
      name.present? &&
        SEVERITIES.include?(severity) &&
        !metric.nil? && metric.is_a?(Core::Domain::Metric) &&
        !threshold.nil? &&
        timestamp.is_a?(Time) &&
        STATUSES.include?(status)
    end

    def validate!
      raise ArgumentError, "Name cannot be empty" if name.nil? || name.empty?
      raise ArgumentError, "Severity must be one of: #{SEVERITIES.join(', ')}" unless SEVERITIES.include?(severity)
      raise ArgumentError, "Metric cannot be nil" if metric.nil?
      raise ArgumentError, "Metric must be a Core::Domain::Metric" unless metric.is_a?(Core::Domain::Metric)
      raise ArgumentError, "Threshold cannot be nil" if threshold.nil?
      raise ArgumentError, "Timestamp must be a Time object" unless timestamp.is_a?(Time)
      raise ArgumentError, "Status must be one of: #{STATUSES.join(', ')}" unless STATUSES.include?(status)
    end

    # Equality methods for testing
    def ==(other)
      return false unless other.is_a?(Alert)

      id == other.id &&
        name == other.name &&
        severity == other.severity &&
        metric == other.metric &&
        threshold == other.threshold &&
        timestamp.to_i == other.timestamp.to_i &&
        status == other.status
    end

    alias eql? ==

    def hash
      [id, name, severity, metric, threshold, timestamp.to_i, status].hash
    end

    # Business logic methods
    def acknowledge
      return self if status == :acknowledged

      self.class.new(
        id: id,
        name: name,
        severity: severity,
        metric: metric,
        threshold: threshold,
        timestamp: timestamp,
        status: :acknowledged
      )
    end

    def resolve
      return self if status == :resolved

      self.class.new(
        id: id,
        name: name,
        severity: severity,
        metric: metric,
        threshold: threshold,
        timestamp: timestamp,
        status: :resolved
      )
    end

    def escalate(new_severity)
      return self if !SEVERITIES.include?(new_severity) || SEVERITIES.index(new_severity) <= SEVERITIES.index(severity)

      self.class.new(
        id: id,
        name: name,
        severity: new_severity,
        metric: metric,
        threshold: threshold,
        timestamp: timestamp,
        status: status
      )
    end

    def active?
      status == :active
    end

    def acknowledged?
      status == :acknowledged
    end

    def resolved?
      status == :resolved
    end

    def critical?
      severity == :critical
    end

    def warning?
      severity == :warning
    end

    def info?
      severity == :info
    end

    def to_h
      {
        id: id,
        name: name,
        severity: severity,
        metric: metric.to_h,
        threshold: threshold,
        timestamp: timestamp,
        status: status
      }
    end

    def with_id(new_id)
      self.class.new(
        id: new_id,
        name: name,
        severity: severity,
        metric: metric,
        threshold: threshold,
        timestamp: timestamp,
        status: status
      )
    end
  end
end
