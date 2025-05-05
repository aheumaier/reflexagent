RSpec.shared_context "event examples" do
  let(:event_id) { SecureRandom.uuid }
  let(:event_name) { "user.login" }
  let(:event_source) { "web_api" }
  let(:event_timestamp) { Time.current }
  let(:event_data) { { user_id: 123, ip_address: "192.168.1.1" } }

  let(:event) do
    Domain::EventFactory.create(
      id: event_id,
      name: event_name,
      source: event_source,
      timestamp: event_timestamp,
      data: event_data
    )
  end

  let(:event_without_id) do
    Domain::EventFactory.create(
      name: event_name,
      source: event_source,
      timestamp: event_timestamp,
      data: event_data
    )
  end
end

RSpec.shared_context "metric examples" do
  let(:metric_id) { SecureRandom.uuid }
  let(:metric_name) { "response_time" }
  let(:metric_value) { 150.5 }
  let(:metric_timestamp) { Time.current }
  let(:metric_source) { "api_gateway" }
  let(:metric_dimensions) { { endpoint: "/users", method: "GET" } }

  let(:metric) do
    Domain::Metric.new(
      id: metric_id,
      name: metric_name,
      value: metric_value,
      timestamp: metric_timestamp,
      source: metric_source,
      dimensions: metric_dimensions
    )
  end

  let(:metric_without_id) do
    Domain::Metric.new(
      name: metric_name,
      value: metric_value,
      timestamp: metric_timestamp,
      source: metric_source,
      dimensions: metric_dimensions
    )
  end
end

RSpec.shared_context "alert examples" do
  include_context "metric examples"

  let(:alert_id) { SecureRandom.uuid }
  let(:alert_name) { "High Response Time" }
  let(:alert_severity) { :warning }
  let(:alert_threshold) { 100 }
  let(:alert_timestamp) { Time.current }
  let(:alert_status) { :active }

  let(:alert) do
    Domain::Alert.new(
      id: alert_id,
      name: alert_name,
      severity: alert_severity,
      metric: metric,
      threshold: alert_threshold,
      timestamp: alert_timestamp,
      status: alert_status
    )
  end

  let(:alert_without_id) do
    Domain::Alert.new(
      name: alert_name,
      severity: alert_severity,
      metric: metric,
      threshold: alert_threshold,
      timestamp: alert_timestamp,
      status: alert_status
    )
  end
end
