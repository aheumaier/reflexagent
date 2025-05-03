# frozen_string_literal: true

require "rails_helper"
require_relative "../../../app/adapters/repositories/storage_adapter"

RSpec.describe Adapters::Repositories::StorageAdapter do
  let(:event_repository) { instance_double(Repositories::EventRepository) }
  let(:metric_repository) { instance_double(Repositories::MetricRepository) }
  let(:alert_repository) { instance_double(Repositories::AlertRepository) }

  let(:adapter) do
    described_class.new(
      event_repository: event_repository,
      metric_repository: metric_repository,
      alert_repository: alert_repository
    )
  end

  describe "event delegation" do
    let(:event) { double("Event", id: "event-1") }

    it "delegates save_event to event repository" do
      allow(event_repository).to receive(:save_event).with(event).and_return(event)
      result = adapter.save_event(event)
      expect(result).to eq(event)
      expect(event_repository).to have_received(:save_event).with(event)
    end

    it "delegates find_event to event repository" do
      allow(event_repository).to receive(:find_event).with("event-1").and_return(event)
      result = adapter.find_event("event-1")
      expect(result).to eq(event)
      expect(event_repository).to have_received(:find_event).with("event-1")
    end

    it "delegates read_events to event repository" do
      events = [double("Event1"), double("Event2")]
      allow(event_repository).to receive(:read_events).with(from_position: 0, limit: 10).and_return(events)
      result = adapter.read_events(from_position: 0, limit: 10)
      expect(result).to eq(events)
      expect(event_repository).to have_received(:read_events).with(from_position: 0, limit: 10)
    end
  end

  describe "metric delegation" do
    let(:metric) { double("Metric", id: "metric-1") }
    let(:metrics) { [double("Metric1"), double("Metric2")] }

    it "delegates save_metric to metric repository" do
      allow(metric_repository).to receive(:save_metric).with(metric).and_return(metric)
      result = adapter.save_metric(metric)
      expect(result).to eq(metric)
      expect(metric_repository).to have_received(:save_metric).with(metric)
    end

    it "delegates find_metric to metric repository" do
      allow(metric_repository).to receive(:find_metric).with("metric-1").and_return(metric)
      result = adapter.find_metric("metric-1")
      expect(result).to eq(metric)
      expect(metric_repository).to have_received(:find_metric).with("metric-1")
    end

    it "delegates list_metrics to metric repository" do
      filters = { name: "cpu.usage" }
      allow(metric_repository).to receive(:list_metrics).with(filters).and_return(metrics)
      result = adapter.list_metrics(filters)
      expect(result).to eq(metrics)
      expect(metric_repository).to have_received(:list_metrics).with(filters)
    end

    it "delegates find_aggregate_metric to metric repository" do
      dimensions = { host: "web-01" }
      allow(metric_repository).to receive(:find_aggregate_metric).with("cpu.usage", dimensions).and_return(metric)
      result = adapter.find_aggregate_metric("cpu.usage", dimensions)
      expect(result).to eq(metric)
      expect(metric_repository).to have_received(:find_aggregate_metric).with("cpu.usage", dimensions)
    end
  end

  describe "alert delegation" do
    let(:alert) { double("Alert", id: "alert-1") }
    let(:alerts) { [double("Alert1"), double("Alert2")] }

    it "delegates save_alert to alert repository" do
      allow(alert_repository).to receive(:save_alert).with(alert).and_return(alert)
      result = adapter.save_alert(alert)
      expect(result).to eq(alert)
      expect(alert_repository).to have_received(:save_alert).with(alert)
    end

    it "delegates find_alert to alert repository" do
      allow(alert_repository).to receive(:find_alert).with("alert-1").and_return(alert)
      result = adapter.find_alert("alert-1")
      expect(result).to eq(alert)
      expect(alert_repository).to have_received(:find_alert).with("alert-1")
    end

    it "delegates list_alerts to alert repository" do
      filters = { severity: :critical }
      allow(alert_repository).to receive(:list_alerts).with(filters).and_return(alerts)
      result = adapter.list_alerts(filters)
      expect(result).to eq(alerts)
      expect(alert_repository).to have_received(:list_alerts).with(filters)
    end
  end
end
