require 'rails_helper'

RSpec.describe Core::Domain::Metric do
  include_context "metric examples"

  describe '#initialize' do
    context 'with all attributes' do
      subject { metric }

      it 'sets all attributes correctly' do
        expect(subject.id).to eq(metric_id)
        expect(subject.name).to eq(metric_name)
        expect(subject.value).to eq(metric_value)
        expect(subject.timestamp).to eq(metric_timestamp)
        expect(subject.source).to eq(metric_source)
        expect(subject.dimensions).to eq(metric_dimensions)
      end
    end

    context 'with required attributes only' do
      subject do
        described_class.new(
          name: metric_name,
          value: metric_value,
          source: metric_source
        )
      end

      it 'sets required attributes correctly' do
        expect(subject.id).to be_nil
        expect(subject.name).to eq(metric_name)
        expect(subject.value).to eq(metric_value)
        expect(subject.source).to eq(metric_source)
        expect(subject.timestamp).to be_a(Time)
        expect(subject.dimensions).to eq({})
      end
    end

    context 'with empty dimensions' do
      subject do
        described_class.new(
          name: metric_name,
          value: metric_value,
          source: metric_source,
          dimensions: {}
        )
      end

      it 'handles empty dimensions correctly' do
        expect(subject.dimensions).to eq({})
      end
    end

    context 'with different value types' do
      subject { metric_value_type }

      context 'with integer value' do
        let(:metric_value_type) do
          described_class.new(
            name: metric_name,
            value: 42,
            source: metric_source
          )
        end

        it 'accepts integer values' do
          expect(subject.value).to eq(42)
        end
      end

      context 'with float value' do
        let(:metric_value_type) do
          described_class.new(
            name: metric_name,
            value: 42.5,
            source: metric_source
          )
        end

        it 'accepts float values' do
          expect(subject.value).to eq(42.5)
        end
      end

      context 'with large value' do
        let(:large_value) { 9_123_456_789 }
        let(:metric_value_type) do
          described_class.new(
            name: metric_name,
            value: large_value,
            source: metric_source
          )
        end

        it 'handles large values correctly' do
          expect(subject.value).to eq(large_value)
        end
      end
    end

    context 'with custom timestamp' do
      let(:custom_time) { Time.new(2023, 1, 1, 12, 0, 0) }

      subject do
        described_class.new(
          name: metric_name,
          value: metric_value,
          source: metric_source,
          timestamp: custom_time
        )
      end

      it 'uses the provided timestamp' do
        expect(subject.timestamp).to eq(custom_time)
      end
    end
  end

  describe 'attributes' do
    subject { metric }

    it 'has read-only attributes' do
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

  describe 'factory' do
    subject { build(:metric) }

    it 'creates a valid metric' do
      expect(subject).to be_a(described_class)
      expect(subject.id).not_to be_nil
      expect(subject.name).not_to be_nil
      expect(subject.value).not_to be_nil
    end

    context 'with traits' do
      subject { build(:metric, :cpu_usage) }

      it 'creates a metric with the specified trait' do
        expect(subject.name).to eq('cpu_usage')
        expect(subject.dimensions[:host]).to eq('web-1')
      end
    end

    context 'with overrides' do
      subject { build(:metric, name: 'custom.metric', value: 999, dimensions: { custom: 'dimension' }) }

      it 'allows overriding default values' do
        expect(subject.name).to eq('custom.metric')
        expect(subject.value).to eq(999)
        expect(subject.dimensions).to eq({ custom: 'dimension' })
      end
    end
  end
end
