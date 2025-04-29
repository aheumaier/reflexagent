require 'rails_helper'

RSpec.describe Core::UseCases::ProcessEvent do
  include_context "with all mock ports"
  include_context "event examples"

  subject(:use_case) { described_class.new(storage_port: mock_storage_port, queue_port: mock_queue_port) }

  describe '#call' do
    context 'with a valid event' do
      it 'saves the event via the storage port' do
        use_case.call(event)

        expect(mock_storage_port.saved_events).to include(event)
      end

      it 'enqueues the event for metric calculation via the queue port' do
        use_case.call(event)

        expect(mock_queue_port.enqueued_events).to include(event)
      end

      it 'processes the event in the correct order' do
        # Using method spies to ensure the correct order of calls
        expect(mock_storage_port).to receive(:save_event).with(event).ordered
        expect(mock_queue_port).to receive(:enqueue_metric_calculation).with(event).ordered

        use_case.call(event)
      end
    end

    context 'with an event without an ID' do
      it 'saves the event and assigns an ID' do
        result = use_case.call(event_without_id)

        expect(mock_storage_port.saved_events.first.id).not_to be_nil
        expect(result).to eq(mock_storage_port.saved_events.first)
      end
    end

    context 'with different event types' do
      let(:login_event) { build(:event, :login) }
      let(:logout_event) { build(:event, :logout) }
      let(:purchase_event) { build(:event, :purchase) }

      it 'processes all event types' do
        use_case.call(login_event)
        use_case.call(logout_event)
        use_case.call(purchase_event)

        expect(mock_storage_port.saved_events).to include(login_event, logout_event, purchase_event)
        expect(mock_queue_port.enqueued_events).to include(login_event, logout_event, purchase_event)
      end
    end
  end

  describe 'factory method' do
    it 'creates the use case with dependencies injected' do
      # Register our mocks with the container
      DependencyContainer.register(:storage_port, mock_storage_port)
      DependencyContainer.register(:queue_port, mock_queue_port)

      # Create use case using factory
      factory_created = UseCaseFactory.create_process_event

      # Verify injected dependencies
      factory_created.call(event)
      expect(mock_storage_port.saved_events).to include(event)
      expect(mock_queue_port.enqueued_events).to include(event)
    end
  end
end
