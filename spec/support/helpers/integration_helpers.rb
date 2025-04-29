module IntegrationHelpers
  # Helper to process a full event through the system
  def process_event_through_system(event)
    # Step 1: Process the event
    process_event_use_case = UseCaseFactory.create_process_event
    process_event_use_case.call(event)

    # Step 2: Calculate metrics (in a real app this would happen via a worker)
    event_id = storage_port.saved_events.last.id
    calculate_metrics_use_case = UseCaseFactory.create_calculate_metrics
    metric = calculate_metrics_use_case.call(event_id)

    # Step 3: Detect anomalies
    metric_id = storage_port.saved_metrics.last.id
    detect_anomalies_use_case = UseCaseFactory.create_detect_anomalies
    alert = detect_anomalies_use_case.call(metric_id)

    # Return the resulting objects
    {
      event: storage_port.saved_events.last,
      metric: storage_port.saved_metrics.last,
      alert: alert
    }
  end

  # Helper to generate high metric values for testing anomaly detection
  def build_high_value_metric(options = {})
    build(:metric, { value: 150 }.merge(options))
  end

  # Helper to generate normal metric values for testing anomaly detection
  def build_normal_value_metric(options = {})
    build(:metric, { value: 50 }.merge(options))
  end
end

RSpec.configure do |config|
  config.include IntegrationHelpers
end
