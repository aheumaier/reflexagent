require 'rails_helper'

RSpec.describe Core::UseCases::DetectAnomalies do
  include_context "with all mock ports"
  include_context "metric examples"

  subject(:use_case) { described_class.new(storage_port: mock_storage_port, notification_port: mock_notification_port) }

  describe '#call' do
    context 'with a high value metric (exceeding threshold)' do
      let(:high_value_metric) do
        build(:metric, value: 150) # Above the threshold of 100
      end
      let(:saved_metric) { mock_storage_port.save_metric(high_value_metric) }
      let(:metric_id) { saved_metric.id }

      before do
        # Store the metric so it can be retrieved by ID
        saved_metric
      end

      it 'retrieves the metric from storage' do
        expect(mock_storage_port).to receive(:find_metric).with(metric_id).and_return(saved_metric)

        use_case.call(metric_id)
      end

      it 'creates an alert for metrics above threshold' do
        result = use_case.call(metric_id)

        expect(result).to be_a(Core::Domain::Alert)
        expect(result.name).to include(high_value_metric.name)
        expect(result.severity).to eq(:warning)
        expect(result.metric).to eq(high_value_metric)
        expect(result.threshold).to eq(100)
      end

      it 'saves the alert via the storage port' do
        use_case.call(metric_id)

        expect(mock_storage_port.saved_alerts.size).to eq(1)
        expect(mock_storage_port.saved_alerts.first.metric).to eq(high_value_metric)
      end

      it 'sends the alert via the notification port' do
        use_case.call(metric_id)

        expect(mock_notification_port.sent_alerts.size).to eq(1)
        expect(mock_notification_port.sent_alerts.first.metric).to eq(high_value_metric)
      end

      it 'processes the alert in the correct order' do
        # Using method spies to ensure the correct order of calls
        expect(mock_storage_port).to receive(:find_metric).with(metric_id).and_return(saved_metric).ordered
        expect(mock_storage_port).to receive(:save_alert).ordered
        expect(mock_notification_port).to receive(:send_alert).ordered

        use_case.call(metric_id)
      end
    end

    context 'with a normal value metric (below threshold)' do
      let(:normal_value_metric) do
        build(:metric, value: 50) # Below the threshold of 100
      end
      let(:saved_metric) { mock_storage_port.save_metric(normal_value_metric) }
      let(:metric_id) { saved_metric.id }

      before do
        # Store the metric so it can be retrieved by ID
        saved_metric
      end

      it 'does not create an alert for metrics below threshold' do
        result = use_case.call(metric_id)

        expect(result).to be_nil
        expect(mock_storage_port.saved_alerts).to be_empty
        expect(mock_notification_port.sent_alerts).to be_empty
      end
    end

    context 'with different metric types' do
      let(:response_time_metric) { mock_storage_port.save_metric(build(:metric, :response_time, value: 150)) }
      let(:cpu_usage_metric) { mock_storage_port.save_metric(build(:metric, :cpu_usage, value: 150)) }
      let(:memory_usage_metric) { mock_storage_port.save_metric(build(:metric, :memory_usage, value: 150)) }

      it 'creates appropriate alerts for each metric type' do
        response_time_alert = use_case.call(response_time_metric.id)
        cpu_usage_alert = use_case.call(cpu_usage_metric.id)
        memory_usage_alert = use_case.call(memory_usage_metric.id)

        expect(response_time_alert.name).to include("response_time")
        expect(cpu_usage_alert.name).to include("cpu_usage")
        expect(memory_usage_alert.name).to include("memory_usage")
      end
    end

    context 'with a non-existent metric ID' do
      let(:nonexistent_id) { 'nonexistent-id' }

      before do
        allow(mock_storage_port).to receive(:find_metric).with(nonexistent_id).and_return(nil)
      end

      it 'raises an error' do
        expect { use_case.call(nonexistent_id) }.to raise_error(NoMethodError)
      end
    end
  end

  describe 'factory method' do
    it 'creates the use case with dependencies injected' do
      # Register our mocks with the container
      DependencyContainer.register(:storage_port, mock_storage_port)
      DependencyContainer.register(:notification_port, mock_notification_port)

      # Store a high value metric for testing
      stored_metric = mock_storage_port.save_metric(build(:metric, value: 150))

      # Create use case using factory
      factory_created = UseCaseFactory.create_detect_anomalies

      # Verify injected dependencies
      factory_created.call(stored_metric.id)
      expect(mock_storage_port.saved_alerts.size).to eq(1)
      expect(mock_notification_port.sent_alerts.size).to eq(1)
    end
  end
end
