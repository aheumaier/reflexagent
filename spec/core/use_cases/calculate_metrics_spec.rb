require 'rails_helper'

RSpec.describe Core::UseCases::CalculateMetrics do
  include_context "with all mock ports"
  include_context "event examples"
  include_context "metric examples"

  subject(:use_case) { described_class.new(storage_port: mock_storage_port, cache_port: mock_cache_port) }

  describe '#call' do
    let(:saved_event) { mock_storage_port.save_event(event) }
    let(:event_id) { saved_event.id }

    context 'with a valid event ID' do
      before do
        # Store the event so it can be retrieved by ID
        saved_event
      end

      it 'retrieves the event from storage' do
        expect(mock_storage_port).to receive(:find_event).with(event_id).and_return(saved_event)

        use_case.call(event_id)
      end

      it 'creates a metric based on the event' do
        result = use_case.call(event_id)

        expect(result).to be_a(Core::Domain::Metric)
        expect(result.name).to eq("#{event.name}_count")
        expect(result.value).to eq(1)
        expect(result.source).to eq(event.source)
        expect(result.dimensions).to eq(event.data)
      end

      it 'saves the metric via the storage port' do
        use_case.call(event_id)

        expect(mock_storage_port.saved_metrics.size).to eq(1)
        expect(mock_storage_port.saved_metrics.first.name).to eq("#{event.name}_count")
      end

      it 'caches the metric via the cache port' do
        use_case.call(event_id)

        expect(mock_cache_port.cached_metrics.size).to eq(1)
        metric_key = mock_cache_port.cached_metrics.keys.first
        expect(metric_key).to include("#{event.name}_count")
      end

      it 'processes the metric in the correct order' do
        # Using method spies to ensure the correct order of calls
        expect(mock_storage_port).to receive(:find_event).with(event_id).and_return(saved_event).ordered
        expect(mock_storage_port).to receive(:save_metric).ordered
        expect(mock_cache_port).to receive(:cache_metric).ordered

        use_case.call(event_id)
      end
    end

    context 'with different event types' do
      let(:login_event) { mock_storage_port.save_event(build(:event, :login)) }
      let(:logout_event) { mock_storage_port.save_event(build(:event, :logout)) }
      let(:purchase_event) { mock_storage_port.save_event(build(:event, :purchase)) }

      it 'creates appropriate metrics for each event type' do
        login_metric = use_case.call(login_event.id)
        logout_metric = use_case.call(logout_event.id)
        purchase_metric = use_case.call(purchase_event.id)

        expect(login_metric.name).to eq("user.login_count")
        expect(logout_metric.name).to eq("user.logout_count")
        expect(purchase_metric.name).to eq("order.purchase_count")

        expect(login_metric.dimensions[:user_id]).to eq(123)
        expect(logout_metric.dimensions[:session_duration]).to eq(3600)
        expect(purchase_metric.dimensions[:order_id]).to eq(456)
      end
    end

    context 'with a non-existent event ID' do
      let(:nonexistent_id) { 'nonexistent-id' }

      before do
        allow(mock_storage_port).to receive(:find_event).with(nonexistent_id).and_return(nil)
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
      DependencyContainer.register(:cache_port, mock_cache_port)

      # Store an event for testing
      stored_event = mock_storage_port.save_event(event)

      # Create use case using factory
      factory_created = UseCaseFactory.create_calculate_metrics

      # Verify injected dependencies
      factory_created.call(stored_event.id)
      expect(mock_storage_port.saved_metrics.size).to eq(1)
      expect(mock_cache_port.cached_metrics.size).to eq(1)
    end
  end
end
