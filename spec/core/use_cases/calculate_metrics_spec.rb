require "rails_helper"

RSpec.describe UseCases::CalculateMetrics do
  subject(:use_case) do
    described_class.new(storage_port: mock_storage_port, cache_port: mock_cache_port,
                        metric_classifier: mock_metric_classifier)
  end

  include_context "with all mock ports"
  include_context "event examples"
  include_context "metric examples"

  let(:mock_metric_classifier) do
    instance_double(Domain::MetricClassifier).tap do |classifier|
      allow(classifier).to receive(:classify_event).and_return({
                                                                 metrics: [
                                                                   {
                                                                     name: "#{event.name}_count",
                                                                     value: 1,
                                                                     dimensions: { source: event.source }
                                                                   }
                                                                 ]
                                                               })
    end
  end

  let(:event) do
    event = Domain::EventFactory.create(
      id: "event-123",
      name: "server.cpu.usage",
      data: { value: 85.5, host: "web-01", region: "us-west" },
      source: "monitoring-agent"
    )
    mock_storage_port.save_event(event)
    event
  end

  describe "#call" do
    it "creates metrics based on the event" do
      result = use_case.call(event.id)

      expect(result).to be_a(Domain::Metric)
      expect(mock_storage_port.saved_metrics.size).to eq(1)
      expect(mock_storage_port.saved_metrics.first.name).to eq("server.cpu.usage_count")
      expect(mock_storage_port.saved_metrics.first.value).to eq(1)
      expect(mock_storage_port.saved_metrics.first.source).to eq("monitoring-agent")
    end

    it "caches the metrics" do
      result = use_case.call(event.id)

      expect(mock_cache_port.cached_metrics.size).to eq(1)
      cached_metric_key = mock_cache_port.cached_metrics.keys.first
      cached_metric = mock_cache_port.cached_metrics[cached_metric_key]
      expect(cached_metric.name).to eq("server.cpu.usage_count")
      expect(cached_metric.value).to eq(1)
    end

    context "when the event does not exist" do
      before do
        allow(mock_storage_port).to receive(:find_event).with("nonexistent-id").and_return(nil)
      end

      it "raises an error" do
        expect { use_case.call("nonexistent-id") }.to raise_error(NoMethodError)
      end
    end

    context "when an error occurs during metric calculation" do
      before do
        allow(mock_storage_port).to receive(:save_metric).and_raise(StandardError.new("Test error"))
      end

      it "propagates the error" do
        expect { use_case.call(event.id) }.to raise_error(StandardError, "Test error")
      end
    end
  end

  describe "factory method" do
    it "creates the use case with dependencies injected" do
      # Register our mocks with the container
      DependencyContainer.register(:storage_port, mock_storage_port)
      DependencyContainer.register(:cache_port, mock_cache_port)
      DependencyContainer.register(:metric_classifier, mock_metric_classifier)

      # Create use case using factory
      factory_created = UseCaseFactory.create_calculate_metrics

      # Verify injected dependencies are working
      result = factory_created.call(event.id)
      expect(result).to be_a(Domain::Metric)
      expect(mock_storage_port.saved_metrics.size).to eq(1)
      expect(mock_cache_port.cached_metrics.size).to eq(1)
    end
  end
end
