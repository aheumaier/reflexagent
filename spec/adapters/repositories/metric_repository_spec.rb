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
    it 'persists the metric to the database and returns it' do
      # Verify the database count before saving
      expect {
        @result = repository.save_metric(metric)
      }.to change(DomainMetric, :count).by(1)

      # Verify the returned metric has the correct values
      expect(@result).to be_a(Core::Domain::Metric)
      expect(@result.name).to eq('cpu.usage')
      expect(@result.value).to eq(85.5)
      expect(@result.source).to eq('web-01')
      expect(@result.dimensions[:region]).to eq('us-west')

      # Verify the database record has the correct values
      db_record = DomainMetric.last
      expect(db_record.name).to eq('cpu.usage')
      expect(db_record.value).to eq(85.5)
      expect(db_record.source).to eq('web-01')
      expect(db_record.dimensions['region']).to eq('us-west')
    end
  end

  describe '#find_metric' do
    it 'retrieves a metric from the database by id' do
      # Save a metric first
      saved_metric = repository.save_metric(metric)

      # Now find it by ID
      found_metric = repository.find_metric(saved_metric.id)

      # Verify the found metric
      expect(found_metric).not_to be_nil
      expect(found_metric.id).to eq(saved_metric.id)
      expect(found_metric.name).to eq('cpu.usage')
      expect(found_metric.value).to eq(85.5)
    end

    it 'returns nil when metric not found' do
      result = repository.find_metric('nonexistent-id')
      expect(result).to be_nil
    end
  end

  describe '#list_metrics' do
    before do
      # Create a few metrics for testing
      repository.save_metric(
        Core::Domain::Metric.new(
          name: 'cpu.usage',
          value: 85.5,
          source: 'web-01',
          dimensions: { region: 'us-west' },
          timestamp: 2.hours.ago
        )
      )

      repository.save_metric(
        Core::Domain::Metric.new(
          name: 'cpu.usage',
          value: 90.2,
          source: 'web-02',
          dimensions: { region: 'us-east' },
          timestamp: 1.hour.ago
        )
      )

      repository.save_metric(
        Core::Domain::Metric.new(
          name: 'memory.usage',
          value: 70.3,
          source: 'web-01',
          dimensions: { region: 'us-west' },
          timestamp: 30.minutes.ago
        )
      )
    end

    it 'returns metrics filtered by name' do
      results = repository.list_metrics(name: 'cpu.usage')
      expect(results.length).to eq(2)
      expect(results.all? { |m| m.name == 'cpu.usage' }).to be(true)
    end

    it 'returns metrics filtered by time range' do
      results = repository.list_metrics(start_time: 90.minutes.ago)
      expect(results.length).to eq(2)
    end

    it 'returns the most recent metrics first when ordered' do
      results = repository.list_metrics(latest_first: true)
      expect(results.first.name).to eq('memory.usage')
    end
  end

  describe '#get_average' do
    before do
      # Create metrics for testing average
      repository.save_metric(
        Core::Domain::Metric.new(
          name: 'cpu.usage',
          value: 80.0,
          source: 'web-01',
          timestamp: 3.hours.ago
        )
      )

      repository.save_metric(
        Core::Domain::Metric.new(
          name: 'cpu.usage',
          value: 90.0,
          source: 'web-01',
          timestamp: 2.hours.ago
        )
      )

      repository.save_metric(
        Core::Domain::Metric.new(
          name: 'cpu.usage',
          value: 70.0,
          source: 'web-01',
          timestamp: 1.hour.ago
        )
      )
    end

    it 'calculates the average value for a metric' do
      average = repository.get_average('cpu.usage')
      expect(average).to eq(80.0)
    end

    it 'calculates the average for a specific time range' do
      average = repository.get_average('cpu.usage', 2.5.hours.ago, 1.5.hours.ago)
      expect(average).to eq(90.0)
    end
  end
end
