# frozen_string_literal: true

require_relative "../../ports/storage_port"
require_relative "../../core/domain/alert"

module Repositories
  class AlertRepository
    include StoragePort

    def initialize(logger_port: nil)
      @alerts_cache = {} # In-memory cache for tests
      @logger_port = logger_port || Rails.logger
    end

    def save_alert(alert)
      # Create metric data hash to serialize
      metric_data = if alert.metric
                      {
                        "id" => alert.metric.id,
                        "metric_name" => alert.metric.name,
                        "metric_value" => alert.metric.value,
                        "source" => alert.metric.source,
                        "dimensions" => alert.metric.dimensions,
                        "timestamp" => alert.metric.timestamp&.iso8601
                      }
                    else
                      {}
                    end

      # Check if an alert with this ID already exists
      existing_alert = nil
      existing_alert = DomainAlert.find_by(id: alert.id) if alert.id.present?

      domain_alert = nil
      if existing_alert
        # Update existing alert
        @logger_port.debug { "Updating existing alert with ID: #{existing_alert.id}" }
        existing_alert.update!(
          name: alert.name,
          severity: alert.severity.to_s,
          metric_data: metric_data,
          threshold: alert.threshold,
          status: alert.status.to_s,
          timestamp: alert.timestamp || Time.current
        )
        domain_alert = existing_alert
      else
        # Create a new alert
        @logger_port.debug { "Creating new alert" }
        domain_alert = DomainAlert.create!(
          name: alert.name,
          severity: alert.severity.to_s,
          metric_data: metric_data,
          threshold: alert.threshold,
          status: alert.status.to_s,
          timestamp: alert.timestamp || Time.current
        )
      end

      # Log the alert ID
      @logger_port.debug { "Alert ID: #{domain_alert.id}" }

      # Convert to a domain alert with the database ID
      alert_with_id = Domain::Alert.new(
        id: domain_alert.id.to_s,
        name: alert.name,
        severity: alert.severity,
        metric: alert.metric,
        threshold: alert.threshold,
        status: domain_alert.status.to_sym,
        timestamp: domain_alert.timestamp
      )

      # Store in memory cache for tests
      @alerts_cache[alert_with_id.id] = alert_with_id

      # Return the domain alert
      alert_with_id
    end

    def find_alert(id)
      # Log the ID we're trying to find
      @logger_port.debug { "Finding alert with ID: #{id}" }

      # Normalize the ID to string
      id_str = id.to_s

      # Try to find in memory cache first (for tests)
      if @alerts_cache.key?(id_str)
        @logger_port.debug { "Found alert in cache: #{id_str}" }
        return @alerts_cache[id_str]
      end

      # Find in database
      domain_alert = DomainAlert.find_by(id: id_str)
      return nil unless domain_alert

      @logger_port.debug { "Found alert in database: #{domain_alert.id}" }

      # Convert to domain model using the model's to_domain_model method
      alert = domain_alert.to_domain_model

      # Cache for future lookups
      @alerts_cache[alert.id] = alert

      alert
    end

    def list_alerts(filters = {})
      scope = DomainAlert.all

      scope = scope.where(status: filters[:status].to_s) if filters[:status].present?
      scope = scope.by_severity(filters[:severity].to_s) if filters[:severity].present?
      scope = scope.where(name: filters[:name]) if filters[:name].present?

      if filters[:from_timestamp].present? && filters[:to_timestamp].present?
        scope = scope.where(timestamp: filters[:from_timestamp]..filters[:to_timestamp])
      elsif filters[:from_timestamp].present?
        scope = scope.where("timestamp >= ?", filters[:from_timestamp])
      elsif filters[:to_timestamp].present?
        scope = scope.where("timestamp <= ?", filters[:to_timestamp])
      end

      scope = scope.where("timestamp >= ?", filters[:start_time]) if filters[:start_time].present?

      scope = scope.limit(filters[:limit]) if filters[:limit].present?

      # Order by timestamp, descending if :recent or :latest_first is true
      order_desc = filters[:recent] || filters[:latest_first]
      scope = order_desc ? scope.order(timestamp: :desc) : scope.order(timestamp: :asc)

      # Convert to domain models
      scope.map(&:to_domain_model)
    end

    private

    def extract_metric_from_alert(domain_alert)
      return nil unless domain_alert.metric_id.present?

      # Create a simplified metric object from the alert data
      Domain::Metric.new(
        id: domain_alert.metric_id.to_s,
        name: domain_alert.metric_name,
        value: domain_alert.metric_value,
        source: "alert",
        dimensions: {},
        timestamp: domain_alert.timestamp
      )
    end
  end
end
