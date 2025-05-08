require "rails_helper"

RSpec.describe UseCases::SendNotification do
  subject(:use_case) { described_class.new(notification_port: mock_notification_port, storage_port: mock_storage_port) }

  include_context "with all mock ports"

  let(:metric) do
    Domain::Metric.new(
      id: "metric-123",
      name: "cpu.usage",
      value: 95.0,
      source: "web-01",
      dimensions: { region: "us-west" }
    )
  end

  let(:alert) do
    alert = Domain::Alert.new(
      id: "alert-123",
      name: "High CPU Usage",
      severity: :warning,
      metric: metric,
      threshold: 90.0
    )
    # Mock storage_port.find_alert to return this alert
    allow(mock_storage_port).to receive(:find_alert).with(alert.id).and_return(alert)
    alert
  end

  describe "#call" do
    it "sends the alert via notification port" do
      use_case.call(alert.id)

      expect(mock_notification_port).to have_received(:send_alert).with(alert)
    end

    context "when the alert does not exist" do
      before do
        allow(mock_storage_port).to receive(:find_alert).with("nonexistent-id").and_return(nil)
      end

      it "sends a nil alert" do
        use_case.call("nonexistent-id")
        expect(mock_notification_port).to have_received(:send_alert).with(nil)
      end
    end

    context "when notification fails" do
      before do
        allow(mock_notification_port).to receive(:send_alert).and_raise(StandardError.new("Notification failed"))
      end

      it "propagates the error" do
        expect { use_case.call(alert.id) }.to raise_error(StandardError, "Notification failed")
      end
    end
  end

  describe "factory method" do
    it "creates the use case with dependencies injected" do
      # Register our mocks with the container
      DependencyContainer.register(:notification_port, mock_notification_port)
      DependencyContainer.register(:alert_repository, mock_storage_port)

      # Create use case using factory
      factory_created = UseCaseFactory.create_send_notification

      # Verify injected dependencies are working
      factory_created.call(alert.id)
      expect(mock_notification_port).to have_received(:send_alert).with(alert)
    end
  end
end
