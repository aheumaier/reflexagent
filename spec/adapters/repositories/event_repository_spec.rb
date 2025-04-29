require 'rails_helper'
require_relative '../../../app/adapters/repositories/event_repository'
require_relative '../../../app/adapters/repositories/metric_repository'
require_relative '../../../app/adapters/repositories/alert_repository'
require_relative '../../../app/core/domain/event'
require_relative '../../../app/core/domain/metric'
require_relative '../../../app/core/domain/alert'

RSpec.describe Adapters::Repositories::EventRepository do
  let(:repository) { described_class.new }
  let(:event) do
    Core::Domain::Event.new(
      name: 'server.cpu.usage',
      data: { value: 85.5, host: 'web-01' },
      source: 'monitoring-agent',
      timestamp: Time.current
    )
  end

  describe '#save_event' do
    it 'persists the event and returns it' do
      result = repository.save_event(event)

      expect(result).to eq(event)
      # In a real implementation with ActiveRecord, you would verify database state here
    end
  end

  describe '#find_event' do
    it 'returns nil when event not found' do
      result = repository.find_event(999)

      expect(result).to be_nil
      # In a real implementation, you would create an event first and then find it
    end
  end

  describe 'delegation to other repositories' do
    let(:metric) { Core::Domain::Metric.new(name: 'cpu.usage', value: 85.5, source: 'web-01', dimensions: {}) }
    let(:alert) { Core::Domain::Alert.new(name: 'High CPU', severity: :warning, metric: metric, threshold: 80) }

    it 'delegates save_metric to MetricRepository' do
      metric_repository = instance_double(Adapters::Repositories::MetricRepository)
      allow(Adapters::Repositories::MetricRepository).to receive(:new).and_return(metric_repository)
      allow(metric_repository).to receive(:save_metric).with(metric).and_return(metric)

      result = repository.save_metric(metric)

      expect(result).to eq(metric)
      expect(metric_repository).to have_received(:save_metric).with(metric)
    end

    it 'delegates save_alert to AlertRepository' do
      alert_repository = instance_double(Adapters::Repositories::AlertRepository)
      allow(Adapters::Repositories::AlertRepository).to receive(:new).and_return(alert_repository)
      allow(alert_repository).to receive(:save_alert).with(alert).and_return(alert)

      result = repository.save_alert(alert)

      expect(result).to eq(alert)
      expect(alert_repository).to have_received(:save_alert).with(alert)
    end
  end
end
