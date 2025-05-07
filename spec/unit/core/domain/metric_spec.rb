require "rails_helper"

RSpec.describe Domain::Metric do
  include_context "metric examples"

  describe "#initialize" do
    context "with all attributes" do
      subject { metric }

      it "sets all attributes correctly" do
        expect(subject.id).to eq(metric_id)
        expect(subject.name).to eq(metric_name)
        expect(subject.value).to eq(metric_value)
        expect(subject.timestamp).to eq(metric_timestamp)
        expect(subject.source).to eq(metric_source)
        expect(subject.dimensions).to eq(metric_dimensions)
      end
    end

    context "with required attributes only" do
      subject do
        described_class.new(
          name: metric_name,
          value: metric_value,
          source: metric_source
        )
      end

      it "sets required attributes correctly" do
        expect(subject.id).to be_nil
        expect(subject.name).to eq(metric_name)
        expect(subject.value).to eq(metric_value)
        expect(subject.source).to eq(metric_source)
        expect(subject.timestamp).to be_a(Time)
        expect(subject.dimensions).to eq({})
      end
    end

    context "with empty dimensions" do
      subject do
        described_class.new(
          name: metric_name,
          value: metric_value,
          source: metric_source,
          dimensions: {}
        )
      end

      it "handles empty dimensions correctly" do
        expect(subject.dimensions).to eq({})
      end
    end

    context "with different value types" do
      subject { metric_value_type }

      context "with integer value" do
        let(:metric_value_type) do
          described_class.new(
            name: metric_name,
            value: 42,
            source: metric_source
          )
        end

        it "accepts integer values" do
          expect(subject.value).to eq(42)
        end
      end

      context "with float value" do
        let(:metric_value_type) do
          described_class.new(
            name: metric_name,
            value: 42.5,
            source: metric_source
          )
        end

        it "accepts float values" do
          expect(subject.value).to eq(42.5)
        end
      end

      context "with large value" do
        let(:large_value) { 9_123_456_789 }
        let(:metric_value_type) do
          described_class.new(
            name: metric_name,
            value: large_value,
            source: metric_source
          )
        end

        it "handles large values correctly" do
          expect(subject.value).to eq(large_value)
        end
      end
    end

    context "with custom timestamp" do
      subject do
        described_class.new(
          name: metric_name,
          value: metric_value,
          source: metric_source,
          timestamp: custom_time
        )
      end

      let(:custom_time) { Time.new(2023, 1, 1, 12, 0, 0) }

      it "uses the provided timestamp" do
        expect(subject.timestamp).to eq(custom_time)
      end
    end
  end

  describe "attributes" do
    subject { metric }

    it "has read-only attributes" do
      expect(subject).to respond_to(:id)
      expect(subject).to respond_to(:name)
      expect(subject).to respond_to(:value)
      expect(subject).to respond_to(:source)
      expect(subject).to respond_to(:timestamp)
      expect(subject).to respond_to(:dimensions)

      # Ensure attributes are read-only
      expect(subject).not_to respond_to(:id=)
      expect(subject).not_to respond_to(:name=)
      expect(subject).not_to respond_to(:value=)
      expect(subject).not_to respond_to(:source=)
      expect(subject).not_to respond_to(:timestamp=)
      expect(subject).not_to respond_to(:dimensions=)
    end
  end

  describe "factory" do
    subject { build(:metric) }

    it "creates a valid metric" do
      expect(subject).to be_a(described_class)
      expect(subject.id).not_to be_nil
      expect(subject.name).not_to be_nil
      expect(subject.value).not_to be_nil
    end

    context "with traits" do
      subject { build(:metric, :cpu_usage) }

      it "creates a metric with the specified trait" do
        expect(subject.name).to eq("cpu_usage")
        expect(subject.dimensions[:host]).to eq("web-1")
      end
    end

    context "with overrides" do
      subject { build(:metric, name: "custom.metric", value: 999, dimensions: { custom: "dimension" }) }

      it "allows overriding default values" do
        expect(subject.name).to eq("custom.metric")
        expect(subject.value).to eq(999)
        expect(subject.dimensions).to eq({ custom: "dimension" })
      end
    end
  end

  # Tests for the new validation methods
  describe "#valid?" do
    it "returns true for a valid metric" do
      expect(metric).to be_valid
    end

    it "raises an error for a metric with empty name" do
      expect do
        described_class.new(
          name: "",
          value: metric_value,
          source: metric_source,
          dimensions: metric_dimensions
        )
      end.to raise_error(ArgumentError, "Name cannot be empty")
    end

    it "raises an error for a metric with nil value" do
      expect do
        described_class.new(
          name: metric_name,
          value: nil,
          source: metric_source,
          dimensions: metric_dimensions
        )
      end.to raise_error(ArgumentError, "Value cannot be nil")
    end

    it "raises an error for a metric with empty source" do
      expect do
        described_class.new(
          name: metric_name,
          value: metric_value,
          source: "",
          dimensions: metric_dimensions
        )
      end.to raise_error(ArgumentError, "Source cannot be empty")
    end

    it "raises an error for a metric with invalid timestamp" do
      expect do
        described_class.new(
          name: metric_name,
          value: metric_value,
          source: metric_source,
          timestamp: "invalid",
          dimensions: metric_dimensions
        )
      end.to raise_error(ArgumentError, "Timestamp must be a Time object")
    end

    it "raises an error for a metric with invalid dimensions" do
      expect do
        described_class.new(
          name: metric_name,
          value: metric_value,
          source: metric_source,
          dimensions: "invalid"
        )
      end.to raise_error(ArgumentError, "Dimensions must be a hash")
    end
  end

  # Tests for equality methods
  describe "#==" do
    it "returns true for identical metrics" do
      metric1 = described_class.new(
        id: metric_id,
        name: metric_name,
        value: metric_value,
        source: metric_source,
        timestamp: metric_timestamp,
        dimensions: metric_dimensions
      )

      metric2 = described_class.new(
        id: metric_id,
        name: metric_name,
        value: metric_value,
        source: metric_source,
        timestamp: metric_timestamp,
        dimensions: metric_dimensions
      )

      expect(metric1).to eq(metric2)
    end

    it "returns false for metrics with different attributes" do
      metric1 = described_class.new(
        id: metric_id,
        name: metric_name,
        value: metric_value,
        source: metric_source,
        timestamp: metric_timestamp,
        dimensions: metric_dimensions
      )

      metric2 = described_class.new(
        id: "different-id",
        name: metric_name,
        value: metric_value,
        source: metric_source,
        timestamp: metric_timestamp,
        dimensions: metric_dimensions
      )

      expect(metric1).not_to eq(metric2)
    end

    it "returns false for different types" do
      expect(metric).not_to eq("not a metric")
    end
  end

  describe "#hash" do
    it "returns the same hash for identical metrics" do
      metric1 = described_class.new(
        id: metric_id,
        name: metric_name,
        value: metric_value,
        source: metric_source,
        timestamp: metric_timestamp,
        dimensions: metric_dimensions
      )

      metric2 = described_class.new(
        id: metric_id,
        name: metric_name,
        value: metric_value,
        source: metric_source,
        timestamp: metric_timestamp,
        dimensions: metric_dimensions
      )

      expect(metric1.hash).to eq(metric2.hash)
    end

    it "returns different hash for different metrics" do
      metric1 = described_class.new(
        id: metric_id,
        name: metric_name,
        value: metric_value,
        source: metric_source,
        timestamp: metric_timestamp,
        dimensions: metric_dimensions
      )

      metric2 = described_class.new(
        id: "different-id",
        name: metric_name,
        value: metric_value,
        source: metric_source,
        timestamp: metric_timestamp,
        dimensions: metric_dimensions
      )

      expect(metric1.hash).not_to eq(metric2.hash)
    end
  end

  # Tests for business logic methods
  describe "#numeric?" do
    it "returns true when value is a number" do
      expect(metric.numeric?).to be true
    end

    it "returns false when value is not a number" do
      string_metric = described_class.new(
        name: metric_name,
        value: "not a number",
        source: metric_source,
        dimensions: metric_dimensions
      )

      expect(string_metric.numeric?).to be false
    end
  end

  describe "#age" do
    it "returns the age of the metric" do
      current_time = Time.now
      allow(Time).to receive(:now).and_return(current_time)

      metric_time = current_time - 3600 # 1 hour ago
      test_metric = described_class.new(
        name: metric_name,
        value: metric_value,
        source: metric_source,
        timestamp: metric_time,
        dimensions: metric_dimensions
      )

      expect(test_metric.age).to be_within(0.001).of(3600)
    end
  end

  describe "#to_h" do
    it "returns a hash representation of the metric" do
      expected_hash = {
        id: metric_id,
        name: metric_name,
        value: metric_value,
        timestamp: metric_timestamp,
        source: metric_source,
        dimensions: metric_dimensions
      }

      expect(metric.to_h).to eq(expected_hash)
    end
  end

  describe "#with_id" do
    it "creates a new metric with the specified id" do
      new_id = "new-id"
      new_metric = metric.with_id(new_id)

      expect(new_metric).not_to eq(metric)
      expect(new_metric.id).to eq(new_id)
      expect(new_metric.name).to eq(metric.name)
      expect(new_metric.value).to eq(metric.value)
      expect(new_metric.source).to eq(metric.source)
      expect(new_metric.timestamp).to eq(metric.timestamp)
      expect(new_metric.dimensions).to eq(metric.dimensions)
    end
  end

  describe "#with_value" do
    it "creates a new metric with the specified value" do
      new_value = 99.9
      new_metric = metric.with_value(new_value)

      expect(new_metric).not_to eq(metric)
      expect(new_metric.id).to eq(metric.id)
      expect(new_metric.name).to eq(metric.name)
      expect(new_metric.value).to eq(new_value)
      expect(new_metric.source).to eq(metric.source)
      expect(new_metric.timestamp).to eq(metric.timestamp)
      expect(new_metric.dimensions).to eq(metric.dimensions)
    end
  end
end
