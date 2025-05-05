require "rails_helper"
require_relative "../../app/adapters/repositories/event_repository"
require_relative "../../app/core/domain/event"

RSpec.describe "Event Persistence", type: :integration do
  include_context "event examples"

  let(:repository) { Adapters::Repositories::EventRepository.new }

  describe "end-to-end persistence" do
    before do
      # Clean the database before each test
      DomainEvent.delete_all
    end

    it "persists domain events using append_event" do
      # Append an event directly to test basic functionality
      event_record = repository.append_event(
        aggregate_id: SecureRandom.uuid,
        event_type: "test.event",
        payload: { test: "data" }
      )

      # Verify the event was persisted
      expect(event_record).to be_a(Domain::Event)
      expect(event_record.id).not_to be_nil
      expect(event_record.name).to eq("test.event")
      expect(DomainEvent.count).to eq(1)

      # Retrieve the record from the database directly
      db_record = DomainEvent.last
      expect(db_record).not_to be_nil
      expect(db_record.event_type).to eq("test.event")
      expect(db_record.payload.with_indifferent_access[:test]).to eq("data")
    end

    it "appends events to a stream" do
      # Create multiple events for the same aggregate
      aggregate_id = SecureRandom.uuid

      # Append events to stream
      repository.append_event(
        aggregate_id: aggregate_id,
        event_type: "user.created",
        payload: { name: "Test User", email: "test@example.com" }
      )

      repository.append_event(
        aggregate_id: aggregate_id,
        event_type: "user.updated",
        payload: { name: "Updated User", email: "test@example.com" }
      )

      # Verify database records were created
      expect(DomainEvent.count).to eq(2)
      expect(DomainEvent.for_aggregate(aggregate_id).count).to eq(2)

      # Read the stream using repository
      stream_events = repository.read_stream(aggregate_id: aggregate_id)

      # Verify stream events
      expect(stream_events.size).to eq(2)
      expect(stream_events.first.name).to eq("user.created")
      expect(stream_events.last.name).to eq("user.updated")

      # Check data with indifferent access
      expect(stream_events.first.data.with_indifferent_access[:name]).to eq("Test User")
      expect(stream_events.last.data.with_indifferent_access[:name]).to eq("Updated User")
    end

    it "reads events chronologically" do
      # Append multiple events
      repository.append_event(
        aggregate_id: SecureRandom.uuid,
        event_type: "event.first",
        payload: { order: 1 }
      )

      repository.append_event(
        aggregate_id: SecureRandom.uuid,
        event_type: "event.second",
        payload: { order: 2 }
      )

      repository.append_event(
        aggregate_id: SecureRandom.uuid,
        event_type: "event.third",
        payload: { order: 3 }
      )

      # Read all events
      all_events = repository.read_events

      # Verify chronological order
      expect(all_events.size).to eq(3)
      expect(all_events.map(&:name)).to eq(["event.first", "event.second", "event.third"])

      # Check data with indifferent access
      orders = all_events.map { |e| e.data.with_indifferent_access[:order] }
      expect(orders).to eq([1, 2, 3])
    end

    it "reads events from a specific position" do
      # Append multiple events
      repository.append_event(
        aggregate_id: SecureRandom.uuid,
        event_type: "event.first",
        payload: { order: 1 }
      )

      # Get the position of the first event
      first_position = DomainEvent.last.position

      # Add more events
      repository.append_event(
        aggregate_id: SecureRandom.uuid,
        event_type: "event.second",
        payload: { order: 2 }
      )

      repository.append_event(
        aggregate_id: SecureRandom.uuid,
        event_type: "event.third",
        payload: { order: 3 }
      )

      # Read events after the first one
      events_after_first = repository.read_events(from_position: first_position)

      # Should include events 2 and 3 (not event 1)
      expect(events_after_first.size).to eq(2)
      expect(events_after_first.map(&:name)).to include("event.second", "event.third")
      expect(events_after_first.map(&:name)).not_to include("event.first")
    end

    it "limits the number of events returned" do
      # Append multiple events
      5.times do |i|
        repository.append_event(
          aggregate_id: SecureRandom.uuid,
          event_type: "event.#{i}",
          payload: { order: i }
        )
      end

      # Read with limit
      limited_events = repository.read_events(limit: 3)

      # Verify limit is respected
      expect(limited_events.size).to eq(3)
    end
  end
end
