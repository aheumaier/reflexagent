require "rails_helper"

RSpec.describe Domain::EventFactory do
  let(:event_name) { "server.cpu.usage" }
  let(:event_source) { "monitoring-agent" }
  let(:event_data) { { value: 85.5, host: "web-01" } }
  let(:event_id) { "event-123" }
  let(:event_timestamp) { Time.current }

  describe ".create" do
    it "creates a new Domain::Event with the provided attributes" do
      event = described_class.create(
        name: event_name,
        source: event_source,
        data: event_data,
        id: event_id,
        timestamp: event_timestamp
      )

      expect(event).to be_a(Domain::Event)
      expect(event.name).to eq(event_name)
      expect(event.source).to eq(event_source)
      expect(event.data).to eq(event_data)
      expect(event.id).to eq(event_id)
      expect(event.timestamp).to eq(event_timestamp)
    end

    it "auto-generates an ID when not provided" do
      event = described_class.create(
        name: event_name,
        source: event_source,
        data: event_data
      )

      expect(event.id).not_to be_nil
      expect(event.id.length).to be > 0
    end

    it "uses current time when timestamp not provided" do
      freeze_time = Time.current
      allow(Time).to receive(:current).and_return(freeze_time)

      event = described_class.create(
        name: event_name,
        source: event_source,
        data: event_data
      )

      expect(event.timestamp).to eq(freeze_time)
    end
  end

  describe ".from_record" do
    let(:record) do
      instance_double("DomainEvent",
                      id: 42,
                      event_type: event_name,
                      aggregate_id: event_source,
                      payload: event_data,
                      created_at: event_timestamp)
    end

    it "creates a Domain::Event from a database record with correct mappings" do
      event = described_class.from_record(record)

      expect(event).to be_a(Domain::Event)
      expect(event.id).to eq("42")
      expect(event.name).to eq(event_name)
      expect(event.source).to eq(event_source)
      expect(event.data).to eq(event_data)
      expect(event.timestamp).to eq(event_timestamp)
    end
  end

  describe ".to_persistence_attributes" do
    let(:event) do
      Domain::Event.new(
        id: event_id,
        name: event_name,
        source: event_source,
        data: event_data,
        timestamp: event_timestamp
      )
    end

    it "converts a Domain::Event to database-ready attributes" do
      attributes = described_class.to_persistence_attributes(event)

      expect(attributes).to be_a(Hash)
      expect(attributes[:event_type]).to eq(event_name)
      expect(attributes[:aggregate_id]).to eq(event_source)
      expect(attributes[:payload]).to eq(event_data)
      expect(attributes.key?(:id)).to be false
      expect(attributes.key?(:created_at)).to be false
    end
  end
end
