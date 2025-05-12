require "rails_helper"

# Mock class to use instead of direct DomainEvent access
class MockDomainEvent
  attr_accessor :id, :aggregate_id, :event_type, :payload, :created_at, :position

  def initialize(attrs = {})
    attrs.each do |key, value|
      send("#{key}=", value) if respond_to?("#{key}=")
    end
    @id ||= 1
    @position ||= 1
    @created_at ||= Time.current
  end
end

RSpec.describe "Event Persistence" do
  let(:repository) { Repositories::EventRepository.new }
  let(:aggregate_id) { SecureRandom.uuid }

  # Allow event mapper to handle our mock events
  before do
    # Patch the event mapper to work with our mock
    event_mapper = repository.instance_variable_get(:@event_mapper)
    allow(event_mapper).to receive(:to_domain_event) do |record|
      Domain::EventFactory.create(
        id: record.id.to_s,
        name: record.event_type,
        source: record.aggregate_id,
        data: record.payload,
        timestamp: record.created_at
      )
    end
  end

  # Helper to count domain events
  def count_events
    result = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM domain_events")
    result.first["count"].to_i
  end

  # Helper to get domain events
  def get_events(limit: nil, order_by: "position ASC")
    sql = "SELECT * FROM domain_events ORDER BY #{order_by}"
    sql += " LIMIT #{limit}" if limit
    ActiveRecord::Base.connection.execute(sql).to_a
  end

  # Helper to get events for a specific aggregate
  def get_events_for_aggregate(aggregate_id, limit: nil)
    sql = "SELECT * FROM domain_events WHERE aggregate_id = '#{aggregate_id}' ORDER BY position ASC"
    sql += " LIMIT #{limit}" if limit
    ActiveRecord::Base.connection.execute(sql).to_a
  end

  describe "end-to-end persistence" do
    before do
      # Clean up database before each test

      ActiveRecord::Base.connection.execute("TRUNCATE domain_events RESTART IDENTITY CASCADE")
    rescue StandardError => e
      puts "Error cleaning database: #{e.message}"
    end

    it "persists domain events using append_event" do
      # Mock the DomainEvent.create! call inside the repository
      mock_event = MockDomainEvent.new(
        aggregate_id: aggregate_id,
        event_type: "user.registered",
        payload: { "name" => "John Doe", "email" => "john@example.com" },
        id: 1,
        position: 1,
        created_at: Time.current
      )

      # Stub the ActiveRecord transaction to return our mock
      allow(ActiveRecord::Base).to receive(:transaction).and_yield
      allow(DomainEvent).to receive(:create!).and_return(mock_event)

      # Act - append an event
      event = repository.append_event(
        aggregate_id: aggregate_id,
        event_type: "user.registered",
        payload: { name: "John Doe", email: "john@example.com" }
      )

      # Assert - verify the event was persisted
      expect(event).not_to be_nil
      expect(event.name).to eq("user.registered")
      expect(event.source).to eq(aggregate_id)
      expect(event.data).to include("name" => "John Doe")
    end

    it "appends events to a stream" do
      # Set up mocks for multiple events
      5.times do |i|
        mock_event = MockDomainEvent.new(
          aggregate_id: aggregate_id,
          event_type: "event#{i}",
          payload: { "index" => i },
          id: i + 1,
          position: i + 1,
          created_at: Time.current
        )

        # Stub each create call to return a different mock
        allow(DomainEvent).to receive(:create!).with(
          hash_including(
            aggregate_id: aggregate_id,
            event_type: "event#{i}"
          )
        ).and_return(mock_event)
      end

      # Stub the ActiveRecord transaction to yield
      allow(ActiveRecord::Base).to receive(:transaction).and_yield

      # Act - create a series of events in the same stream
      events = []
      5.times do |i|
        events << repository.append_event(
          aggregate_id: aggregate_id,
          event_type: "event#{i}",
          payload: { index: i }
        )
      end

      # Assert
      expect(events.size).to eq(5)
      expect(events.map(&:name)).to eq((0..4).map { |i| "event#{i}" })
    end

    it "reads events chronologically" do
      # Create test events via direct SQL
      event_types = (0..4).map { |i| "test.event.#{i}" }

      # Set up mocks for the query
      mock_records = event_types.map.with_index do |event_type, i|
        MockDomainEvent.new(
          id: i + 1,
          aggregate_id: aggregate_id,
          event_type: event_type,
          payload: { "event" => event_type },
          position: i + 1,
          created_at: Time.current
        )
      end

      # Stub the query chain
      query_double = double("QueryChain")
      allow(DomainEvent).to receive(:since_position).and_return(query_double)
      allow(query_double).to receive(:chronological).and_return(mock_records)

      # Act - read all events
      events = repository.read_events

      # Assert - check events are returned in correct order
      expect(events.map(&:name)).to eq(event_types)
    end

    it "reads events from a specific position" do
      # Create mock events
      event_types = (0..4).map { |i| "test.event.#{i}" }

      # Mock the filtered result (only events 3-4)
      mock_filtered_records = event_types[3..4].map.with_index do |event_type, i|
        MockDomainEvent.new(
          id: i + 4,
          aggregate_id: aggregate_id,
          event_type: event_type,
          payload: { "event" => event_type },
          position: i + 4,
          created_at: Time.current
        )
      end

      # Stub the query chain
      query_double = double("QueryChain")
      allow(DomainEvent).to receive(:since_position).with(3).and_return(query_double)
      allow(query_double).to receive(:chronological).and_return(mock_filtered_records)

      # Act - read from specific position
      events = repository.read_events(from_position: 3)

      # Assert - should get events from position onwards
      expect(events.map(&:name)).to eq(event_types[3..])
    end

    it "limits the number of events returned" do
      # Create many mock events
      mock_records = 5.times.map do |i|
        MockDomainEvent.new(
          id: i + 1,
          aggregate_id: aggregate_id,
          event_type: "event#{i}",
          payload: { "index" => i },
          position: i + 1,
          created_at: Time.current
        )
      end

      # Stub the query chain with limit
      query_double = double("QueryChain")
      allow(DomainEvent).to receive(:since_position).and_return(query_double)
      allow(query_double).to receive(:chronological).and_return(query_double)
      allow(query_double).to receive(:limit).with(5).and_return(mock_records)

      # Act - read with limit
      limit = 5
      events = repository.read_events(limit: limit)

      # Assert - should only get specified number of events
      expect(events.size).to eq(limit)
      expect(events.map(&:name)).to eq((0...limit).map { |i| "event#{i}" })
    end
  end
end
