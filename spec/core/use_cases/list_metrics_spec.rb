require 'rails_helper'

RSpec.describe Core::UseCases::ListMetrics do
  include_context "with all mock ports"

  let(:metrics) do
    [
      Core::Domain::Metric.new(
        id: 'metric-1',
        name: 'cpu_usage',
        value: 85.5,
        source: 'web-server',
        dimensions: { host: 'web-01', region: 'us-west' }
      ),
      Core::Domain::Metric.new(
        id: 'metric-2',
        name: 'memory_usage',
        value: 70.2,
        source: 'db-server',
        dimensions: { host: 'db-01', region: 'us-east' }
      ),
      Core::Domain::Metric.new(
        id: 'metric-3',
        name: 'cpu_usage',
        value: 55.1,
        source: 'api-server',
        dimensions: { host: 'api-01', region: 'us-west' }
      )
    ]
  end

  let(:use_case) { described_class.new(storage_port: mock_storage_port) }

  before do
    # Mock the list_metrics method of the storage port to return metrics
    allow(mock_storage_port).to receive(:list_metrics).and_return(metrics)
    allow(mock_storage_port).to receive(:list_metrics).with({ name: 'cpu_usage' }).and_return(
      metrics.select { |m| m.name == 'cpu_usage' }
    )
    allow(mock_storage_port).to receive(:list_metrics).with({ region: 'us-west' }).and_return(
      metrics.select { |m| m.dimensions[:region] == 'us-west' }
    )
  end

  describe '#call' do
    context 'without filters' do
      it 'returns all metrics' do
        result = use_case.call

        expect(result).to eq(metrics)
        expect(result.size).to eq(3)
      end
    end

    context 'with name filter' do
      it 'returns metrics filtered by name' do
        result = use_case.call({ name: 'cpu_usage' })

        expect(result.size).to eq(2)
        expect(result.all? { |m| m.name == 'cpu_usage' }).to be true
      end
    end

    context 'with dimension filter' do
      it 'returns metrics filtered by dimension' do
        result = use_case.call({ region: 'us-west' })

        expect(result.size).to eq(2)
        expect(result.all? { |m| m.dimensions[:region] == 'us-west' }).to be true
      end
    end
  end

  describe 'factory method' do
    it 'creates the use case with dependencies injected' do
      # Register our mock with the container
      DependencyContainer.register(:storage_port, mock_storage_port)

      # Create use case using factory
      factory_created = UseCaseFactory.create_list_metrics

      # Verify injected dependencies are working
      result = factory_created.call

      expect(result).to eq(metrics)
      expect(result.size).to eq(3)
    end
  end
end
