require 'rails_helper'
require_relative '../../../app/adapters/queue/process_event_worker'
require_relative '../../../app/core/domain/event'
require_relative '../../../app/core/domain/metric'

RSpec.describe Adapters::Queue::ProcessEventWorker do
  let(:worker) { described_class.new }
  let(:event) do
    Core::Domain::Event.new(
      name: 'server.cpu.usage',
      data: { value: 85.5, host: 'web-01' },
      source: 'monitoring-agent'
    )
  end
  let(:metric) do
    Core::Domain::Metric.new(
      name: 'cpu.usage',
      value: 85.5,
      source: 'web-01',
      dimensions: { region: 'us-west', environment: 'production' }
    )
  end

  # In a real implementation, these tests would verify Sidekiq job enqueuing
  # using the Sidekiq testing API

  describe '#enqueue_metric_calculation' do
    it 'enqueues a job to calculate metrics from the event' do
      # In a real implementation with Sidekiq, this would:
      # 1. Configure Sidekiq test mode
      # 2. Verify the job was enqueued with the correct arguments
      result = worker.enqueue_metric_calculation(event)

      expect(result).to be true
    end
  end

  describe '#enqueue_anomaly_detection' do
    it 'enqueues a job to detect anomalies based on the metric' do
      # In a real implementation with Sidekiq, this would:
      # 1. Configure Sidekiq test mode
      # 2. Verify the job was enqueued with the correct arguments
      result = worker.enqueue_anomaly_detection(metric)

      expect(result).to be true
    end
  end
end
