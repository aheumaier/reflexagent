require "rails_helper"

RSpec.describe UseCases::FindMetric do
  include_context "with all mock ports"

  let(:metric) do
    Domain::Metric.new(
      id: "test-metric-id",
      name: "cpu_usage",
      value: 85.5,
      source: "web-server",
      dimensions: { host: "web-01", region: "us-west" },
      timestamp: Time.current
    )
  end

  let(:use_case) { described_class.new(storage_port: mock_storage_port) }

  before do
    # Pre-save a metric in the mock storage
    mock_storage_port.save_metric(metric)
  end

  describe "#call" do
    context "when the metric exists" do
      it "returns the metric with the given ID" do
        result = use_case.call("test-metric-id")

        expect(result).to eq(metric)
        expect(result.id).to eq("test-metric-id")
        expect(result.name).to eq("cpu_usage")
        expect(result.value).to eq(85.5)
      end
    end

    context "when the metric does not exist" do
      it "raises an ArgumentError" do
        expect do
          use_case.call("non-existent-id")
        end.to raise_error(ArgumentError, "Metric with ID 'non-existent-id' not found")
      end
    end
  end

  describe "factory method" do
    it "creates the use case with dependencies injected" do
      # Register our mock with the container
      DependencyContainer.register(:storage_port, mock_storage_port)

      # Create use case using factory
      factory_created = UseCaseFactory.create_find_metric

      # Verify injected dependencies are working
      result = factory_created.call("test-metric-id")

      expect(result).to eq(metric)
      expect(result.id).to eq("test-metric-id")
    end
  end
end
