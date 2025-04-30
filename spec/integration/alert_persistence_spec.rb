require 'rails_helper'
require_relative '../../app/adapters/repositories/alert_repository'
require_relative '../../app/models/domain_alert'
require_relative '../../app/core/domain/alert'
require_relative '../../app/core/domain/metric'

RSpec.describe "Alert Persistence", type: :integration do
  include_context "alert examples"

  let(:repository) { ::Adapters::Repositories::AlertRepository.new }

  describe "end-to-end persistence" do
    before do
      # Clean the database before each test
      DomainAlert.delete_all
    end

    it "persists domain alerts to the database and retrieves them" do
      # Create a domain alert
      domain_alert = repository.save_alert(alert)

      # Verify the domain alert was persisted
      expect(domain_alert.id).not_to be_nil
      expect(DomainAlert.count).to eq(1)

      # Retrieve the record from the database directly
      db_record = DomainAlert.find_by(id: domain_alert.id)
      expect(db_record).not_to be_nil
      expect(db_record.name).to eq(alert.name)
      expect(db_record.severity).to eq(alert.severity.to_s)
      expect(db_record.status).to eq(alert.status.to_s)
      expect(db_record.threshold).to eq(alert.threshold)

      # Verify metric data was stored correctly
      expect(db_record.metric_data["metric_name"]).to eq(alert.metric.name)
      expect(db_record.metric_data["metric_value"]).to eq(alert.metric.value)
      expect(db_record.metric_data["source"]).to eq(alert.metric.source)

      # Retrieve via repository
      retrieved_alert = repository.find_alert(domain_alert.id)

      # Verify domain model conversion worked correctly
      expect(retrieved_alert).to be_a(Core::Domain::Alert)
      expect(retrieved_alert.id).to eq(domain_alert.id)
      expect(retrieved_alert.name).to eq(alert.name)
      expect(retrieved_alert.severity).to eq(alert.severity)
      expect(retrieved_alert.status).to eq(alert.status)
      expect(retrieved_alert.threshold).to eq(alert.threshold)

      # Verify metric conversion
      expect(retrieved_alert.metric).to be_a(Core::Domain::Metric)
      expect(retrieved_alert.metric.name).to eq(alert.metric.name)
      expect(retrieved_alert.metric.value).to eq(alert.metric.value)
      expect(retrieved_alert.metric.source).to eq(alert.metric.source)
    end

    it "updates existing alerts" do
      # Create initial alert
      saved_alert = repository.save_alert(alert)
      original_id = saved_alert.id

      # Modify the alert
      updated_alert = saved_alert.acknowledge

      # Save the updated alert
      result = repository.save_alert(updated_alert)

      # Verify the update worked
      expect(result.id).to eq(original_id)
      expect(result.status).to eq(:acknowledged)

      # Check database directly
      expect(DomainAlert.count).to eq(1)
      expect(DomainAlert.first.status).to eq("acknowledged")

      # Retrieve via repository to confirm
      retrieved = repository.find_alert(original_id)
      expect(retrieved.status).to eq(:acknowledged)
    end

    it "filters alerts correctly" do
      # Create multiple alerts with different properties
      repository.save_alert(build(:alert, :info, :active, name: "Low CPU Alert"))
      repository.save_alert(build(:alert, :warning, :acknowledged, name: "Medium CPU Alert"))
      repository.save_alert(build(:alert, :critical, :resolved, name: "High CPU Alert"))

      # Verify total count
      expect(DomainAlert.count).to eq(3)

      # Test filtering by status
      active_alerts = repository.list_alerts(status: :active)
      expect(active_alerts.size).to eq(1)
      expect(active_alerts.first.name).to eq("Low CPU Alert")

      # Test filtering by severity
      critical_alerts = repository.list_alerts(severity: :critical)
      expect(critical_alerts.size).to eq(1)
      expect(critical_alerts.first.name).to eq("High CPU Alert")

      # Test filtering by name
      medium_alerts = repository.list_alerts(name: "Medium CPU Alert")
      expect(medium_alerts.size).to eq(1)
      expect(medium_alerts.first.severity).to eq(:warning)

      # Test combined filters
      resolved_critical = repository.list_alerts(status: :resolved, severity: :critical)
      expect(resolved_critical.size).to eq(1)
      expect(resolved_critical.first.name).to eq("High CPU Alert")
    end
  end
end
