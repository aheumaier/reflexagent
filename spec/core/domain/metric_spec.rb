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
  end
end
