require 'rails_helper'

RSpec.describe Core::Domain::Event do
  include_context "event examples"

  describe '#initialize' do
    context 'with all attributes' do
      subject { event }

      it 'sets all attributes correctly' do
        expect(subject.id).to eq(event_id)
        expect(subject.name).to eq(event_name)
        expect(subject.source).to eq(event_source)
        expect(subject.timestamp).to eq(event_timestamp)
        expect(subject.data).to eq(event_data)
      end
    end

    context 'with required attributes only' do
      subject do
        described_class.new(
          name: event_name,
          source: event_source
        )
      end

      it 'sets required attributes correctly' do
        expect(subject.id).to be_nil
        expect(subject.name).to eq(event_name)
        expect(subject.source).to eq(event_source)
        expect(subject.timestamp).to be_a(Time)
        expect(subject.data).to eq({})
      end
    end

    context 'with empty data' do
      subject do
        described_class.new(
          name: event_name,
          source: event_source,
          data: {}
        )
      end

      it 'handles empty data correctly' do
        expect(subject.data).to eq({})
      end
    end

    context 'with custom timestamp' do
      let(:custom_time) { Time.new(2023, 1, 1, 12, 0, 0) }

      subject do
        described_class.new(
          name: event_name,
          source: event_source,
          timestamp: custom_time
        )
      end

      it 'uses the provided timestamp' do
        expect(subject.timestamp).to eq(custom_time)
      end
    end
  end

  describe 'attributes' do
    subject { event }

    it 'has read-only attributes' do
      expect(subject).to respond_to(:id)
      expect(subject).to respond_to(:name)
      expect(subject).to respond_to(:source)
      expect(subject).to respond_to(:timestamp)
      expect(subject).to respond_to(:data)

      # Ensure attributes are read-only
      expect(subject).not_to respond_to(:id=)
      expect(subject).not_to respond_to(:name=)
      expect(subject).not_to respond_to(:source=)
      expect(subject).not_to respond_to(:timestamp=)
      expect(subject).not_to respond_to(:data=)
    end
  end

  describe 'factory' do
    subject { build(:event) }

    it 'creates a valid event' do
      expect(subject).to be_a(described_class)
      expect(subject.id).not_to be_nil
      expect(subject.name).not_to be_nil
      expect(subject.source).not_to be_nil
    end

    context 'with traits' do
      subject { build(:event, :purchase) }

      it 'creates an event with the specified trait' do
        expect(subject.name).to eq('order.purchase')
        expect(subject.data[:order_id]).to eq(456)
      end
    end

    context 'with overrides' do
      subject { build(:event, name: 'custom.event', data: { custom: 'value' }) }

      it 'allows overriding default values' do
        expect(subject.name).to eq('custom.event')
        expect(subject.data).to eq({ custom: 'value' })
      end
    end
  end
end
