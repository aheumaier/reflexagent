module UseCaseHelpers
  # Helper for running a use case through its complete lifecycle
  def execute_use_case(use_case, *args)
    use_case.call(*args)
  end

  # Helper for test setup - registers a bunch of events
  def register_sample_events(storage_port, count = 3)
    events = []
    count.times do |i|
      event = build(:event, id: "event-#{i}", name: "test.event.#{i}")
      events << storage_port.save_event(event)
    end
    events
  end

  # Helper for test setup - registers a bunch of metrics
  def register_sample_metrics(storage_port, count = 3)
    metrics = []
    count.times do |i|
      metric = build(:metric, id: "metric-#{i}", name: "test.metric.#{i}")
      metrics << storage_port.save_metric(metric)
    end
    metrics
  end

  # Helper for test setup - registers a bunch of alerts
  def register_sample_alerts(storage_port, metrics, count = 3)
    alerts = []
    count.times do |i|
      metric = metrics[i % metrics.length]
      alert = build(:alert, id: "alert-#{i}", name: "test.alert.#{i}", metric: metric)
      alerts << storage_port.save_alert(alert)
    end
    alerts
  end
end

RSpec.configure do |config|
  config.include UseCaseHelpers
end
