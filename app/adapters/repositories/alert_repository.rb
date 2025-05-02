# frozen_string_literal: true

require_relative "../../ports/storage_port"

module Repositories
  class AlertRepository
    include StoragePort

    def save_alert(alert)
      domain_alert = DomainAlert.from_domain_model(alert)
      domain_alert.to_domain_model.with_id(domain_alert.id.to_s)
    end

    def find_alert(id)
      domain_alert = DomainAlert.find_by(id: id)
      domain_alert&.to_domain_model
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

      scope = scope.limit(filters[:limit]) if filters[:limit].present?
      scope = filters[:recent] ? scope.order(timestamp: :desc) : scope.order(timestamp: :asc)

      scope.map(&:to_domain_model)
    end
  end
end
