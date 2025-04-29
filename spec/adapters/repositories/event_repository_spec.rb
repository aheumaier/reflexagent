require 'rails_helper'
require_relative '../../../app/adapters/repositories/event_repository'
require_relative '../../../app/adapters/repositories/metric_repository'
require_relative '../../../app/adapters/repositories/alert_repository'
require_relative '../../../app/core/domain/event'
require_relative '../../../app/core/domain/metric'
require_relative '../../../app/core/domain/alert'
require_relative '../../../app/models/domain_event'

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
  let(:aggregate_id) { SecureRandom.uuid }

  describe '#save_event' do
    it 'persists the event and returns it' do
      result = repository.save_event(event)

      # ID will be assigned, so we should check other attributes
      expect(result.name).to eq(event.name)
      expect(result.data).to eq(event.data)
      expect(result.source).to eq(event.source)
      expect(result.id).not_to be_nil
    end
  end

  describe '#find_event' do
    it 'returns nil when event not found' do
      result = repository.find_event(999)

      expect(result).to be_nil
    end
  end

  describe '#append_event' do
    it 'persists the event to the database' do
      event_type = 'user.registered'
      payload = { "email" => "test@example.com", "name" => "Test User" }

      expect {
        repository.append_event(
          aggregate_id: aggregate_id,
          event_type: event_type,
          payload: payload
        )
      }.to change(DomainEvent, :count).by(1)

      event = DomainEvent.last
      expect(event.aggregate_id).to eq(aggregate_id)
      expect(event.event_type).to eq(event_type)
      expect(event.payload).to eq(payload)
    end
  end

  describe '#read_events' do
    before do
      # Create some test events
      3.times do |i|
        DomainEvent.create!(
          aggregate_id: aggregate_id,
          event_type: "event.#{i}",
          payload: { "index" => i }
        )
      end
    end

    it 'returns all events in chronological order' do
      events = repository.read_events
      expect(events.size).to eq(3)
      expect(events.map(&:name)).to eq(['event.0', 'event.1', 'event.2'])
    end

    it 'respects from_position parameter' do
      position = DomainEvent.first.position
      events = repository.read_events(from_position: position)
      expect(events.size).to eq(2)
      expect(events.map(&:name)).to eq(['event.1', 'event.2'])
    end

    it 'respects limit parameter' do
      events = repository.read_events(limit: 2)
      expect(events.size).to eq(2)
      expect(events.map(&:name)).to eq(['event.0', 'event.1'])
    end
  end

  describe '#read_stream' do
    let(:another_aggregate_id) { SecureRandom.uuid }

    before do
      # Create events for the first aggregate
      2.times do |i|
        DomainEvent.create!(
          aggregate_id: aggregate_id,
          event_type: "event.#{i}",
          payload: { "index" => i }
        )
      end

      # Create events for another aggregate
      DomainEvent.create!(
        aggregate_id: another_aggregate_id,
        event_type: "other.event",
        payload: { "different" => true }
      )
    end

    it 'returns only events for the specified aggregate' do
      events = repository.read_stream(aggregate_id: aggregate_id)
      expect(events.size).to eq(2)
      expect(events.all? { |e| e.data["index"].is_a?(Integer) }).to be true
    end

    it 'respects from_position parameter' do
      position = DomainEvent.first.position
      events = repository.read_stream(aggregate_id: aggregate_id, from_position: position)
      expect(events.size).to eq(1)
      expect(events.first.name).to eq('event.1')
    end

    it 'respects limit parameter' do
      # Create more events for better testing limit
      DomainEvent.create!(
        aggregate_id: aggregate_id,
        event_type: "event.more",
        payload: { "index" => 100 }
      )

      events = repository.read_stream(aggregate_id: aggregate_id, limit: 2)
      expect(events.size).to eq(2)
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
