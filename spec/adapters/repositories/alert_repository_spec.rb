require "rails_helper"
require_relative "../../../app/adapters/repositories/alert_repository"
require_relative "../../../app/core/domain/alert"
require_relative "../../../app/core/domain/metric"

RSpec.describe Repositories::AlertRepository do
  subject(:repository) { described_class.new }

  include_context "alert examples"

  describe "#save_alert" do
    it "persists the alert to the database" do
      result = repository.save_alert(alert)

      expect(result).to be_a(Domain::Alert)
      expect(result.id).not_to be_nil
      expect(result.name).to eq(alert.name)
      expect(result.severity).to eq(alert.severity)
      expect(result.threshold).to eq(alert.threshold)
      expect(result.status).to eq(alert.status)

      # Verify it's in the database
      expect(DomainAlert.count).to eq(1)
      expect(DomainAlert.first.name).to eq(alert.name)
    end

    it "updates an existing alert" do
      saved = repository.save_alert(alert)
      new_status = :acknowledged
      updated_alert = saved.acknowledge

      result = repository.save_alert(updated_alert)

      expect(result.id).to eq(saved.id)
      expect(result.status).to eq(new_status)
      expect(DomainAlert.count).to eq(1)
      expect(DomainAlert.first.status).to eq(new_status.to_s)
    end
  end

  describe "#find_alert" do
    it "returns nil for non-existent alert" do
      expect(repository.find_alert("non-existent")).to be_nil
    end

    it "finds an alert by id" do
      saved = repository.save_alert(alert)
      result = repository.find_alert(saved.id)

      expect(result).not_to be_nil
      expect(result.id).to eq(saved.id)
      expect(result.name).to eq(alert.name)
    end
  end

  describe "#list_alerts" do
    before do
      # Create alerts with different severities and statuses
      repository.save_alert(build(:alert, :info, :active, name: "Info Alert"))
      repository.save_alert(build(:alert, :warning, :acknowledged, name: "Warning Alert"))
      repository.save_alert(build(:alert, :critical, :resolved, name: "Critical Alert"))
    end

    it "lists all alerts without filters" do
      alerts = repository.list_alerts
      expect(alerts.size).to eq(3)
    end

    it "filters by status" do
      alerts = repository.list_alerts(status: :active)
      expect(alerts.size).to eq(1)
      expect(alerts.first.status).to eq(:active)
    end

    it "filters by severity" do
      alerts = repository.list_alerts(severity: :critical)
      expect(alerts.size).to eq(1)
      expect(alerts.first.severity).to eq(:critical)
    end

    it "filters by name" do
      alerts = repository.list_alerts(name: "Warning Alert")
      expect(alerts.size).to eq(1)
      expect(alerts.first.name).to eq("Warning Alert")
    end

    it "orders by timestamp" do
      alerts = repository.list_alerts(recent: true)
      expect(alerts.size).to eq(3)
      # Most recent should be first
      expect(alerts.first.timestamp).to be >= alerts.last.timestamp
    end

    it "limits results" do
      alerts = repository.list_alerts(limit: 2)
      expect(alerts.size).to eq(2)
    end
  end
end
