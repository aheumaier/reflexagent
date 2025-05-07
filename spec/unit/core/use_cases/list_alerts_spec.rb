require "rails_helper"

RSpec.describe UseCases::ListAlerts do
  include_context "with all mock ports"
  include_context "metric examples"

  let(:alerts) do
    [
      Domain::Alert.new(
        id: "alert-1",
        name: "High CPU Usage",
        severity: :warning,
        metric: metric,
        threshold: 80.0,
        status: :active
      ),
      Domain::Alert.new(
        id: "alert-2",
        name: "Database Latency",
        severity: :critical,
        metric: metric,
        threshold: 100.0,
        status: :acknowledged
      ),
      Domain::Alert.new(
        id: "alert-3",
        name: "Memory Usage",
        severity: :info,
        metric: metric,
        threshold: 75.0,
        status: :resolved
      )
    ]
  end

  let(:use_case) { described_class.new(storage_port: mock_storage_port) }

  before do
    # Mock the list_alerts method of the storage port to return alerts
    allow(mock_storage_port).to receive(:list_alerts).and_return(alerts)
    allow(mock_storage_port).to receive(:list_alerts).with({ severity: :warning }).and_return(
      alerts.select { |a| a.severity == :warning }
    )
    allow(mock_storage_port).to receive(:list_alerts).with({ status: :active }).and_return(
      alerts.select { |a| a.status == :active }
    )
  end

  describe "#call" do
    context "without filters" do
      it "returns all alerts" do
        result = use_case.call

        expect(result).to eq(alerts)
        expect(result.size).to eq(3)
      end
    end

    context "with severity filter" do
      it "returns alerts filtered by severity" do
        result = use_case.call({ severity: :warning })

        expect(result.size).to eq(1)
        expect(result.first.severity).to eq(:warning)
      end
    end

    context "with status filter" do
      it "returns alerts filtered by status" do
        result = use_case.call({ status: :active })

        expect(result.size).to eq(1)
        expect(result.first.status).to eq(:active)
      end
    end
  end

  describe "factory method" do
    it "creates the use case with dependencies injected" do
      # Register our mock with the container
      DependencyContainer.register(:alert_repository, mock_storage_port)

      # Create use case using factory
      factory_created = UseCaseFactory.create_list_alerts

      # Verify injected dependencies are working
      result = factory_created.call

      expect(result).to eq(alerts)
      expect(result.size).to eq(3)
    end
  end
end
