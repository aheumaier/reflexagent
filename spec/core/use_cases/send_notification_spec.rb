require 'rails_helper'

RSpec.describe Core::UseCases::SendNotification do
  include_context "with all mock ports"
  include_context "alert examples"

  subject(:use_case) { described_class.new(notification_port: mock_notification_port, storage_port: mock_storage_port) }

  describe '#call' do
    context 'with a valid alert ID' do
      let(:saved_alert) { mock_storage_port.save_alert(alert) }
      let(:alert_id) { saved_alert.id }

      before do
        # Store the alert so it can be retrieved by ID
        saved_alert
      end

      it 'retrieves the alert from storage' do
        expect(mock_storage_port).to receive(:find_alert).with(alert_id).and_return(saved_alert)

        use_case.call(alert_id)
      end

      it 'sends the alert via the notification port' do
        use_case.call(alert_id)

        expect(mock_notification_port.sent_alerts).to include(saved_alert)
      end

      it 'processes the notification in the correct order' do
        # Using method spies to ensure the correct order of calls
        expect(mock_storage_port).to receive(:find_alert).with(alert_id).and_return(saved_alert).ordered
        expect(mock_notification_port).to receive(:send_alert).with(saved_alert).ordered

        use_case.call(alert_id)
      end
    end

    context 'with different alert severities' do
      let(:info_alert) { mock_storage_port.save_alert(build(:alert, :info)) }
      let(:warning_alert) { mock_storage_port.save_alert(build(:alert, :warning)) }
      let(:critical_alert) { mock_storage_port.save_alert(build(:alert, :critical)) }

      it 'sends notification for all alert severities' do
        use_case.call(info_alert.id)
        use_case.call(warning_alert.id)
        use_case.call(critical_alert.id)

        expect(mock_notification_port.sent_alerts).to include(info_alert, warning_alert, critical_alert)
      end
    end

    context 'with different alert types' do
      let(:response_time_alert) { mock_storage_port.save_alert(build(:alert, :high_response_time)) }
      let(:cpu_usage_alert) { mock_storage_port.save_alert(build(:alert, :high_cpu_usage)) }

      it 'sends notification for all alert types' do
        use_case.call(response_time_alert.id)
        use_case.call(cpu_usage_alert.id)

        expect(mock_notification_port.sent_alerts).to include(response_time_alert, cpu_usage_alert)
      end
    end

    context 'with a non-existent alert ID' do
      let(:nonexistent_id) { 'nonexistent-id' }

      before do
        allow(mock_storage_port).to receive(:find_alert).with(nonexistent_id).and_return(nil)
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

      # Store an alert for testing
      stored_alert = mock_storage_port.save_alert(alert)

      # Create use case using factory
      factory_created = UseCaseFactory.create_send_notification

      # Verify injected dependencies
      factory_created.call(stored_alert.id)
      expect(mock_notification_port.sent_alerts.size).to eq(1)
      expect(mock_notification_port.sent_alerts).to include(stored_alert)
    end
  end
end
