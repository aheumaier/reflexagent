require "rails_helper"

RSpec.describe Core::UseCases::DetectAnomalies do
  subject(:use_case) { described_class.new(storage_port: mock_storage_port, notification_port: mock_notification_port) }

  include_context "with all mock ports"

  let(:normal_metric) do
    Domain::Metric.new(
      id: "metric-123",
      name: "cpu.usage",
      value: 50.0, # Below threshold
      source: "web-01",
      dimensions: { region: "us-west" }
    )
  end

  let(:anomalous_metric) do
    Domain::Metric.new(
      id: "metric-456",
      name: "cpu.usage",
      value: 150.0, # Above threshold (100)
      source: "web-02",
      dimensions: { region: "us-west" }
    )
  end

  describe "#call" do
    context "when metric is within normal range" do
      before do
        mock_storage_port.save_metric(normal_metric)
      end

      it "does not create an alert" do
        result = use_case.call(normal_metric.id)

        expect(result).to be_nil
        expect(mock_storage_port.saved_alerts).to be_empty
        expect(mock_notification_port.sent_alerts).to be_empty
      end
    end

    context "when metric exceeds threshold" do
      before do
        mock_storage_port.save_metric(anomalous_metric)
      end

      it "creates and saves an alert" do
        result = use_case.call(anomalous_metric.id)

        expect(result).to be_a(Core::Domain::Alert)
        expect(mock_storage_port.saved_alerts.size).to eq(1)

        alert = mock_storage_port.saved_alerts.first
        expect(alert.severity).to eq(:warning)
        expect(alert.metric).to eq(anomalous_metric)
        expect(alert.threshold).to eq(100)
      end

      it "sends a notification about the alert" do
        use_case.call(anomalous_metric.id)

        expect(mock_notification_port.sent_alerts.size).to eq(1)

        sent_alert = mock_notification_port.sent_alerts.first
        expect(sent_alert.metric).to eq(anomalous_metric)
      end

      it "processes the alert in the correct order" do
        expect(mock_storage_port).to receive(:find_metric).with(anomalous_metric.id).and_return(anomalous_metric).ordered
        expect(mock_storage_port).to receive(:save_alert).ordered
        expect(mock_notification_port).to receive(:send_alert).ordered

        use_case.call(anomalous_metric.id)
      end
    end

    context "when the metric does not exist" do
      before do
        allow(mock_storage_port).to receive(:find_metric).with("nonexistent-id").and_return(nil)
      end

      it "raises an error" do
        expect { use_case.call("nonexistent-id") }.to raise_error(NoMethodError)
      end
    end

    context "when an error occurs during alert creation" do
      before do
        mock_storage_port.save_metric(anomalous_metric)
        allow(mock_storage_port).to receive(:save_alert).and_raise(StandardError.new("Test error"))
      end

      it "propagates the error" do
        expect { use_case.call(anomalous_metric.id) }.to raise_error(StandardError, "Test error")
      end
    end
  end

  describe "factory method" do
    it "creates the use case with dependencies injected" do
      # Register our mocks with the container
      DependencyContainer.register(:storage_port, mock_storage_port)
      DependencyContainer.register(:notification_port, mock_notification_port)

      # Store a metric for testing
      mock_storage_port.save_metric(anomalous_metric)

      # Create use case using factory
      factory_created = UseCaseFactory.create_detect_anomalies

      # Verify injected dependencies are working
      result = factory_created.call(anomalous_metric.id)
      expect(result).to be_a(Core::Domain::Alert)
      expect(mock_storage_port.saved_alerts.size).to eq(1)
      expect(mock_notification_port.sent_alerts.size).to eq(1)
    end
  end
end
