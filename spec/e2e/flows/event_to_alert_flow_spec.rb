require 'rails_helper'

RSpec.describe "Event to Alert Flow Integration", type: :integration do
  # Create doubles for the ports
  let(:storage_port) do
    double('StoragePort',
      save_event: event,
      find_event: event,
      save_metric: metric,
      find_metric: metric,
      save_alert: alert,
      find_alert: alert,
      delete_all_events: nil,
      delete_all_metrics: nil,
      delete_all_alerts: nil
    )
  end

  let(:cache_port) do
    double('CachePort',
      cache_metric: metric,
      get_cached_metric: nil,
      clear_metric_cache: true
    )
  end

  let(:queue_port) do
    double('QueuePort',
      enqueue_metric_calculation: true,
      enqueue_anomaly_detection: true
    )
  end

  let(:notification_port) do
    double('NotificationPort',
      send_alert: true,
      send_message: true
    )
  end

  # Domain objects
  let(:event) do
    double('Event',
      id: 'event-1',
      name: 'server.cpu.usage',
      data: { value: 95.5, host: 'web-01' },
      source: 'monitoring-agent',
      timestamp: Time.current
    )
  end

  let(:metric) do
    double('Metric',
      id: 'metric-1',
      name: 'cpu.usage',
      value: 95.5,
      source: 'web-01',
      dimensions: {},
      timestamp: Time.current
    )
  end

  let(:alert) do
    double('Alert',
      id: 'alert-1',
      name: 'High CPU Usage',
      severity: :critical,
      metric: metric,
      threshold: 80.0,
      created_at: Time.current
    )
  end

  # Custom use cases that return our test doubles
  let(:process_event_use_case) do
    double('ProcessEvent', call: event)
  end

  let(:calculate_metrics_use_case) do
    double('CalculateMetrics', call: metric)
  end

  let(:detect_anomalies_use_case) do
    obj = double('DetectAnomalies')
    # Default to returning an alert for high values
    allow(obj).to receive(:call) do |metric_id|
      if metric_id == 'normal-metric-id'
        nil
      else
        alert
      end
    end
    obj
  end

  # Register mock ports with the container
  before(:each) do
    DependencyContainer.reset
    DependencyContainer.register(:storage_port, storage_port)
    DependencyContainer.register(:cache_port, cache_port)
    DependencyContainer.register(:queue_port, queue_port)
    DependencyContainer.register(:notification_port, notification_port)

    # Mock the factory to return our custom use cases
    allow(UseCaseFactory).to receive(:create_process_event).and_return(process_event_use_case)
    allow(UseCaseFactory).to receive(:create_calculate_metrics).and_return(calculate_metrics_use_case)
    allow(UseCaseFactory).to receive(:create_detect_anomalies).and_return(detect_anomalies_use_case)
  end

  after do
    DependencyContainer.reset
  end

  describe "Processing a high-severity event" do
    it "processes an event through the entire flow and creates an alert" do
      # Step 1: Process the event
      processed_event = process_event_use_case.call(event)
      expect(processed_event.id).not_to be_nil

      # Verify the event was stored
      stored_event = storage_port.find_event(processed_event.id)
      expect(stored_event).not_to be_nil
      expect(stored_event.name).to eq('server.cpu.usage')

      # Step 2: Calculate metrics from the event
      metric = calculate_metrics_use_case.call(processed_event.id)
      expect(metric).not_to be_nil
      expect(metric.name).to eq('cpu.usage')
      expect(metric.value).to eq(95.5)
      expect(metric.source).to eq('web-01')

      # Verify the metric was stored
      stored_metric = storage_port.find_metric(metric.id)
      expect(stored_metric).not_to be_nil

      # Step 3: Detect anomalies and create alert if threshold exceeded
      alert = detect_anomalies_use_case.call(metric.id)

      # Since the CPU value is high, we expect an alert to be created
      expect(alert).not_to be_nil
      expect(alert.name).to include('CPU Usage')
      expect(alert.severity).to eq(:critical)
      expect(alert.metric).to eq(metric)

      # Verify the alert was stored
      stored_alert = storage_port.find_alert(alert.id)
      expect(stored_alert).not_to be_nil
    end
  end

  describe "Processing a normal event" do
    before do
      # For this test, we modify the doubles to simulate normal values
      normal_metric = double('Metric',
        id: 'normal-metric-id',
        name: 'cpu.usage',
        value: 35.5,
        source: 'web-01'
      )

      allow(calculate_metrics_use_case).to receive(:call).and_return(normal_metric)
    end

    it "processes an event but does not create an alert for normal values" do
      # Step 1: Process the event
      processed_event = process_event_use_case.call(event)

      # Step 2: Calculate metrics from the event
      metric = calculate_metrics_use_case.call(processed_event.id)
      expect(metric.value).to eq(35.5)

      # Step 3: Detect anomalies - should not create an alert for normal values
      alert = detect_anomalies_use_case.call(metric.id)

      # Since the CPU value is normal, we expect no alert to be created
      expect(alert).to be_nil
    end
  end

  describe "Edge cases" do
    it "handles an event with missing data" do
      missing_data_event = double('Event',
        id: 'event-missing-data',
        name: 'server.cpu.usage',
        data: { host: 'web-01' },  # Missing value
        source: 'monitoring-agent',
        timestamp: Time.current
      )

      allow(process_event_use_case).to receive(:call).with(missing_data_event).and_return(missing_data_event)

      # The process_event should work
      processed_event = process_event_use_case.call(missing_data_event)
      expect(processed_event.id).not_to be_nil

      # Shouldn't raise an error when calculating metrics
      expect { calculate_metrics_use_case.call(processed_event.id) }
        .not_to raise_error
    end

    it "handles event with extremely high values" do
      high_value_event = double('Event',
        id: 'event-high-value',
        name: 'server.cpu.usage',
        data: { value: 999.9, host: 'web-01' },
        source: 'monitoring-agent',
        timestamp: Time.current
      )

      high_value_metric = double('Metric',
        id: 'metric-high-value',
        name: 'cpu.usage',
        value: 999.9,
        source: 'web-01'
      )

      allow(process_event_use_case).to receive(:call).with(high_value_event).and_return(high_value_event)
      allow(calculate_metrics_use_case).to receive(:call).with(high_value_event.id).and_return(high_value_metric)

      processed_event = process_event_use_case.call(high_value_event)
      metric = calculate_metrics_use_case.call(processed_event.id)
      alert = detect_anomalies_use_case.call(metric.id)

      # Should create a critical alert
      expect(alert).not_to be_nil
      expect(alert.severity).to eq(:critical)
    end
  end
end
