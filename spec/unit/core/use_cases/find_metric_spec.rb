require "rails_helper"

RSpec.describe UseCases::FindMetric do
  let(:metric_repository) { instance_double("StoragePort") }
  let(:use_case) { described_class.new(storage_port: metric_repository) }

  describe "#call" do
    let(:test_metric) { { id: "test-metric-id", name: "Test Metric" } }

    context "when the metric exists" do
      before do
        allow(metric_repository).to receive(:find_metric).with("test-metric-id").and_return(test_metric)
      end

      it "returns the metric with the given ID" do
        result = use_case.call("test-metric-id")
        expect(result).to eq(test_metric)
      end
    end

    context "when the metric does not exist" do
      before do
        allow(metric_repository).to receive(:find_metric).with("non-existent-id").and_return(nil)
      end

      it "raises an ArgumentError" do
        expect { use_case.call("non-existent-id") }.to raise_error(ArgumentError)
      end
    end
  end

  describe "factory method" do
    let(:test_metric) { { id: "test-metric-id", name: "Test Metric" } }

    before do
      allow(metric_repository).to receive(:find_metric).with("test-metric-id").and_return(test_metric)
      DependencyContainer.register(:metric_repository, metric_repository)
    end

    after do
      DependencyContainer.reset
    end

    it "creates the use case with dependencies injected" do
      factory_created = UseCaseFactory.create_find_metric
      result = factory_created.call("test-metric-id")
      expect(result).to eq(test_metric)
    end
  end
end
