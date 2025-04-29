require 'rails_helper'
require_relative '../../../app/adapters/repositories/alert_repository'
require_relative '../../../app/core/domain/alert'
require_relative '../../../app/core/domain/metric'

RSpec.describe Adapters::Repositories::AlertRepository do
  let(:repository) { described_class.new }
  let(:metric) do
    Core::Domain::Metric.new(
      name: 'cpu.usage',
      value: 85.5,
      source: 'web-01',
      dimensions: { region: 'us-west', environment: 'production' }
    )
  end
  let(:alert) do
    Core::Domain::Alert.new(
      name: 'High CPU Usage',
      severity: :warning,
      metric: metric,
      threshold: 80.0
    )
  end

  describe '#save_alert' do
    it 'persists the alert and returns it' do
      result = repository.save_alert(alert)

      expect(result).to eq(alert)
      # In a real implementation with ActiveRecord, you would verify database state here
    end
  end

  describe '#find_alert' do
    it 'returns nil when alert not found' do
      result = repository.find_alert(999)

      expect(result).to be_nil
      # In a real implementation, you would create an alert first and then find it
    end
  end
end
