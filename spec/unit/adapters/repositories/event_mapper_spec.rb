# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repositories::EventMapper, type: :unit do
  let(:mapper) { described_class.new }

  let(:event) do
    Domain::Event.new(
      id: "123",
      name: "test.event",
      source: "test-source",
      data: { "value" => 123 },
      timestamp: Time.current
    )
  end

  let(:record) do
    instance_double(
      DomainEvent,
      id: 123,
      aggregate_id: "test-aggregate-id",
      event_type: "test.event.type",
      payload: { "key" => "value" },
      created_at: Time.current
    )
  end

  describe "#to_record_attributes" do
    it "maps domain event to record attributes" do
      result = mapper.to_record_attributes(event)

      expect(result).to be_a(Hash)
      expect(result[:event_type]).to eq("test.event")
      expect(result[:payload]).to eq({ "value" => 123 })
      # The aggregate_id will be transformed
      expect(result).to have_key(:aggregate_id)
    end

    context "when source is a valid UUID" do
      let(:uuid) { "550e8400-e29b-41d4-a716-446655440000" }
      let(:event_with_uuid) do
        Domain::Event.new(
          id: "123",
          name: "test.event",
          source: uuid,
          data: { "value" => 123 },
          timestamp: Time.current
        )
      end

      it "uses the UUID directly" do
        result = mapper.to_record_attributes(event_with_uuid)

        expect(result[:aggregate_id]).to eq(uuid)
      end
    end

    context "when source is not a valid UUID" do
      it "generates a UUID" do
        allow(mapper).to receive(:generate_uuid_from_string).and_return("generated-uuid")

        result = mapper.to_record_attributes(event)

        expect(result[:aggregate_id]).to eq("generated-uuid")
      end
    end
  end

  describe "#to_domain_event" do
    it "maps database record to domain event" do
      result = mapper.to_domain_event(record)

      expect(result).to be_a(Domain::Event)
      expect(result.id).to eq("123")
      expect(result.name).to eq("test.event.type")
      expect(result.source).to eq("test-aggregate-id")
      expect(result.data).to eq({ "key" => "value" })
    end
  end

  describe "#event_id_to_aggregate_id" do
    context "with valid UUID" do
      let(:uuid) { "550e8400-e29b-41d4-a716-446655440000" }

      it "returns the UUID unchanged" do
        result = mapper.event_id_to_aggregate_id(uuid)

        expect(result).to eq(uuid)
      end
    end

    context "with non-UUID string" do
      it "generates a UUID" do
        result1 = mapper.event_id_to_aggregate_id("test-source")

        expect(result1).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
      end
    end
  end
end
