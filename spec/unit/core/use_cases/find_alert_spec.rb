require "rails_helper"

RSpec.describe UseCases::FindAlert do
  include_context "with all mock ports"
  include_context "metric examples"

  let(:alert) do
    Domain::Alert.new(
      id: "test-alert-id",
      name: "High CPU Usage",
      severity: :warning,
      metric: metric,
      threshold: 80.0,
      timestamp: Time.current,
      status: :active
    )
  end

  let(:use_case) { described_class.new(storage_port: mock_storage_port) }

  before do
    # Pre-save an alert in the mock storage
    mock_storage_port.save_alert(alert)
  end

  describe "#call" do
    context "when the alert exists" do
      it "returns the alert with the given ID" do
        result = use_case.call("test-alert-id")

        expect(result).to eq(alert)
        expect(result.id).to eq("test-alert-id")
        expect(result.name).to eq("High CPU Usage")
        expect(result.severity).to eq(:warning)
      end
    end

    context "when the alert does not exist" do
      it "raises an ArgumentError" do
        expect do
          use_case.call("non-existent-id")
        end.to raise_error(ArgumentError, "Alert with ID 'non-existent-id' not found")
      end
    end
  end

  describe "factory method" do
    it "creates the use case with dependencies injected" do
      # Register our mock with the container
      DependencyContainer.register(:alert_repository, mock_storage_port)

      # Create use case using factory
      factory_created = UseCaseFactory.create_find_alert

      # Verify injected dependencies are working
      result = factory_created.call("test-alert-id")

      expect(result).to eq(alert)
      expect(result.id).to eq("test-alert-id")
    end
  end
end
