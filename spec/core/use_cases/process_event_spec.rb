require 'rails_helper'

RSpec.describe Core::UseCases::ProcessEvent do
  include_context "with all mock ports"

  let(:event) do
    Core::Domain::Event.new(
      name: 'server.cpu.usage',
      data: { value: 85.5, host: 'web-01' },
      source: 'monitoring-agent',
      timestamp: Time.current
    )
  end

  subject(:use_case) { described_class.new(storage_port: mock_storage_port, queue_port: mock_queue_port) }

  describe '#call' do
    it 'saves the event via the storage port' do
      # Since the storage port adds an ID, we need to look for the event
      # based on properties other than the ID
      result = use_case.call(event)

      expect(mock_storage_port.saved_events.size).to eq(1)
      saved_event = mock_storage_port.saved_events.first
      expect(saved_event.name).to eq('server.cpu.usage')
      expect(saved_event.data[:value]).to eq(85.5)
      expect(saved_event.source).to eq('monitoring-agent')
    end

    it 'enqueues the event for metric calculation via the queue port' do
      use_case.call(event)

      expect(mock_queue_port.enqueued_events.size).to eq(1)
      expect(mock_queue_port.enqueued_events.first.name).to eq('server.cpu.usage')
    end

    it 'processes the event in the correct order' do
      # Using method spies to ensure the correct order of calls
      expect(mock_storage_port).to receive(:save_event).ordered
      expect(mock_queue_port).to receive(:enqueue_metric_calculation).ordered

      use_case.call(event)
    end

    it 'assigns an ID to the event if none exists' do
      event_without_id = Core::Domain::Event.new(
        name: 'server.cpu.usage',
        data: { value: 85.5, host: 'web-01' },
        source: 'monitoring-agent',
        timestamp: Time.current
      )

      use_case.call(event_without_id)

      saved_event = mock_storage_port.saved_events.first
      expect(saved_event.id).not_to be_nil
    end

    context 'when an error occurs' do
      before do
        allow(mock_storage_port).to receive(:save_event).and_raise(StandardError.new('Test error'))
      end

      it 'propagates the error' do
        expect { use_case.call(event) }.to raise_error(StandardError, 'Test error')
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

      # Verify injected dependencies are working
      factory_created.call(event)

      expect(mock_storage_port.saved_events.size).to eq(1)
      saved_event = mock_storage_port.saved_events.first
      expect(saved_event.name).to eq('server.cpu.usage')

      expect(mock_queue_port.enqueued_events.size).to eq(1)
      enqueued_event = mock_queue_port.enqueued_events.first
      expect(enqueued_event.name).to eq('server.cpu.usage')
    end
  end
end
