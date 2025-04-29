require 'rails_helper'
require_relative '../../../app/adapters/repositories/metric_repository'
require_relative '../../../app/core/domain/metric'

RSpec.describe Adapters::Repositories::MetricRepository do
  let(:repository) { described_class.new }
  let(:metric) do
    Core::Domain::Metric.new(
      name: 'cpu.usage',
      value: 85.5,
      source: 'web-01',
      dimensions: { region: 'us-west', environment: 'production' },
      timestamp: Time.current
    )
  end

  describe '#save_metric' do
    it 'persists the metric and returns it' do
      result = repository.save_metric(metric)

      expect(result).to eq(metric)
      # In a real implementation with ActiveRecord, you would verify database state here
    end
  end

  describe '#find_metric' do
    it 'returns nil when metric not found' do
      result = repository.find_metric(999)

      expect(result).to be_nil
      # In a real implementation, you would create a metric first and then find it
    end
  end
end
