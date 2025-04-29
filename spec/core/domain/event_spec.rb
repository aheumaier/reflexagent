require 'rails_helper'

RSpec.describe Core::Domain::Event do
  let(:event_id) { SecureRandom.uuid }
  let(:event_name) { 'user.login' }
  let(:event_source) { 'web_api' }
  let(:event_timestamp) { Time.current }
  let(:event_data) { { user_id: 123, ip_address: '192.168.1.1' } }

  describe '#initialize' do
    context 'with all attributes' do
      subject(:event) do
        described_class.new(
          id: event_id,
          name: event_name,
          source: event_source,
          timestamp: event_timestamp,
          data: event_data
        )
      end

      it 'sets all attributes correctly' do
        expect(event.id).to eq(event_id)
        expect(event.name).to eq(event_name)
        expect(event.source).to eq(event_source)
        expect(event.timestamp).to eq(event_timestamp)
        expect(event.data).to eq(event_data)
      end
    end

    context 'with required attributes only' do
      subject(:event) do
        described_class.new(
          name: event_name,
          source: event_source
        )
      end

      it 'sets required attributes correctly' do
        expect(event.id).to be_nil
        expect(event.name).to eq(event_name)
        expect(event.source).to eq(event_source)
        expect(event.timestamp).to be_a(Time)
        expect(event.data).to eq({})
      end
    end
  end
end
