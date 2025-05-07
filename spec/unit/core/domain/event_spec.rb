require "rails_helper"

RSpec.describe Domain::Event do
  include_context "event examples"

  describe "#initialize" do
    context "with all attributes" do
      subject { event }

      it "sets all attributes correctly" do
        expect(subject.id).to eq(event_id)
        expect(subject.name).to eq(event_name)
        expect(subject.source).to eq(event_source)
        expect(subject.timestamp).to eq(event_timestamp)
        expect(subject.data).to eq(event_data)
      end
    end

    context "with required attributes only" do
      subject do
        described_class.new(
          name: event_name,
          source: event_source,
          data: {}
        )
      end

      it "sets required attributes correctly" do
        # The Event implementation always assigns an ID
        expect(subject.id).not_to be_nil
        expect(subject.id).to be_a(String)
        expect(subject.name).to eq(event_name)
        expect(subject.source).to eq(event_source)
        expect(subject.timestamp).to be_a(Time)
        expect(subject.data).to eq({})
      end
    end

    context "with empty data" do
      subject do
        described_class.new(
          name: event_name,
          source: event_source,
          data: {}
        )
      end

      it "handles empty data correctly" do
        expect(subject.data).to eq({})
      end
    end

    context "with custom timestamp" do
      subject do
        described_class.new(
          name: event_name,
          source: event_source,
          data: {},
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
    subject { event }

    it "has read-only attributes" do
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

  describe "factory" do
    subject { build(:event) }

    it "creates a valid event" do
      expect(subject).to be_a(described_class)
      expect(subject.id).not_to be_nil
      expect(subject.name).not_to be_nil
      expect(subject.source).not_to be_nil
    end

    context "with traits" do
      subject { build(:event, :purchase) }

      it "creates an event with the specified trait" do
        expect(subject.name).to eq("order.purchase")
        expect(subject.data[:order_id]).to eq(456)
      end
    end

    context "with overrides" do
      subject { build(:event, name: "custom.event", data: { custom: "value" }) }

      it "allows overriding default values" do
        expect(subject.name).to eq("custom.event")
        expect(subject.data).to eq({ custom: "value" })
      end
    end
  end

  describe "validations" do
    it "allows valid events" do
      expect { event }.not_to raise_error
    end

    it "raises error for an event with empty name" do
      expect do
        described_class.new(name: "", source: event_source, data: {})
      end.to raise_error(ArgumentError, "Event name cannot be blank")
    end

    it "raises error for an event with empty source" do
      expect do
        described_class.new(name: event_name, source: "", data: {})
      end.to raise_error(ArgumentError, "Event source cannot be blank")
    end

    it "raises error for an event with invalid timestamp" do
      expect do
        described_class.new(name: event_name, source: event_source, data: {}, timestamp: "invalid")
      end.to raise_error(ArgumentError, "Event timestamp must be a Time")
    end

    it "raises error for an event with invalid data" do
      expect do
        described_class.new(name: event_name, source: event_source, data: "invalid")
      end.to raise_error(ArgumentError, "Event data must be a Hash")
    end
  end

  # Tests for equality methods
  describe "#==" do
    it "returns true for identical events" do
      event1 = described_class.new(
        id: event_id,
        name: event_name,
        source: event_source,
        timestamp: event_timestamp,
        data: event_data
      )

      event2 = described_class.new(
        id: event_id,
        name: event_name,
        source: event_source,
        timestamp: event_timestamp,
        data: event_data
      )

      expect(event1).to eq(event2)
    end

    it "returns false for events with different attributes" do
      event1 = described_class.new(
        id: event_id,
        name: event_name,
        source: event_source,
        timestamp: event_timestamp,
        data: event_data
      )

      event2 = described_class.new(
        id: "different-id",
        name: event_name,
        source: event_source,
        timestamp: event_timestamp,
        data: event_data
      )

      expect(event1).not_to eq(event2)
    end

    it "returns false for different types" do
      expect(event).not_to eq("not an event")
    end
  end

  describe "#hash" do
    it "returns the same hash for identical events" do
      event1 = described_class.new(
        id: event_id,
        name: event_name,
        source: event_source,
        timestamp: event_timestamp,
        data: event_data
      )

      event2 = described_class.new(
        id: event_id,
        name: event_name,
        source: event_source,
        timestamp: event_timestamp,
        data: event_data
      )

      expect(event1.hash).to eq(event2.hash)
    end

    it "returns different hash for different events" do
      event1 = described_class.new(
        id: event_id,
        name: event_name,
        source: event_source,
        timestamp: event_timestamp,
        data: event_data
      )

      event2 = described_class.new(
        id: "different-id",
        name: event_name,
        source: event_source,
        timestamp: event_timestamp,
        data: event_data
      )

      expect(event1.hash).not_to eq(event2.hash)
    end
  end

  # Tests for business logic methods
  describe "#age" do
    it "returns the age of the event" do
      current_time = Time.now
      allow(Time).to receive(:now).and_return(current_time)

      event_time = current_time - 3600 # 1 hour ago
      test_event = described_class.new(
        name: event_name,
        source: event_source,
        data: {},
        timestamp: event_time
      )

      expect(test_event.age).to be_within(0.001).of(3600)
    end
  end

  describe "#to_h" do
    it "returns a hash representation of the event" do
      # Use iso8601 format to match the implementation
      expected_hash = {
        id: event_id,
        name: event_name,
        source: event_source,
        timestamp: event_timestamp.iso8601,
        data: event_data
      }

      expect(event.to_h).to eq(expected_hash)
    end
  end

  describe "#with_id" do
    it "creates a new event with the specified id" do
      new_id = "new-id"
      new_event = event.with_id(new_id)

      expect(new_event).not_to eq(event)
      expect(new_event.id).to eq(new_id)
      expect(new_event.name).to eq(event.name)
      expect(new_event.source).to eq(event.source)
      expect(new_event.timestamp).to eq(event.timestamp)
      expect(new_event.data).to eq(event.data)
    end
  end
end
