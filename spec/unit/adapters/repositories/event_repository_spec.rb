# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repositories::EventRepository do
  let(:logger) { instance_double("Logger", debug: nil, info: nil, warn: nil, error: nil) }
  let(:event_mapper) { instance_double("Repositories::EventMapper") }
  let(:repository) { described_class.new(event_mapper: event_mapper, logger_port: logger) }

  let(:test_event) do
    event = Domain::Event.new(
      name: "test.event",
      data: { "key" => "value" },
      source: "test-source",
      timestamp: Time.current
    )

    allow(event).to receive(:with_id) do |id|
      Domain::Event.new(
        id: id,
        name: "test.event",
        data: { "key" => "value" },
        source: "test-source",
        timestamp: Time.current
      )
    end

    event
  end

  # Create the DomainEvent class first, before creating the instance_double
  before(:all) do
    # First undefine if already defined to ensure a clean mock
    Object.send(:remove_const, :DomainEvent) if defined?(DomainEvent)

    # Define the class fresh
    domain_event_model = Class.new do
      attr_accessor :id, :name, :payload, :source, :position, :created_at, :errors

      def initialize(attrs = {})
        attrs.each do |key, value|
          instance_variable_set("@#{key}", value) if respond_to?("#{key}=")
        end
        @created_at ||= Time.current
        @errors = nil
      end

      def save!
        true
      end

      # Define class methods within the class
      class << self
        def create!(attrs = {})
          new(attrs)
        end

        def find_by(conditions = {})
          nil
        end

        def all
          []
        end

        def for_aggregate(*)
          nil
        end

        def since_position(*)
          nil
        end

        def where(*)
          nil
        end

        def chronological
          nil
        end
      end
    end

    Object.const_set("DomainEvent", domain_event_model)
  end

  let(:domain_event_record) do
    # Create actual instance for testing (not instance_double)
    DomainEvent.new(
      id: 123,
      name: "test.event",
      payload: { "key" => "value" },
      source: "test-source",
      position: 1,
      created_at: Time.current
    )
  end

  let(:lookup_strategy) { instance_double("Repositories::EventLookupStrategy", find_record: nil) }
  let(:lookup_factory) { class_double("Repositories::EventLookupStrategyFactory", for_id: lookup_strategy) }

  # Setup mocks
  before do
    # Configure the logger to be correctly called
    allow(logger).to receive(:error).with(any_args)
    allow(logger).to receive(:error) { |&block| block.call if block }

    stub_const("Repositories::EventLookupStrategyFactory", lookup_factory)
    allow(lookup_factory).to receive(:for_id).and_return(lookup_strategy)
    allow(lookup_strategy).to receive(:find_record).and_return(nil)

    # Mock ActiveRecord errors
    stub_const("ActiveRecord::RecordNotFound", Class.new(StandardError))
    stub_const("ActiveRecord::StatementInvalid", Class.new(StandardError) do
      def initialize(message = "SQL error")
        super
      end
    end)
    stub_const("ActiveRecord::ConnectionNotEstablished", Class.new(StandardError))

    record_invalid = Class.new(StandardError) do
      attr_reader :record

      def initialize(record = nil)
        @record = record
        super("Record Invalid")
      end
    end
    stub_const("ActiveRecord::RecordInvalid", record_invalid)

    # Stub methods on event_mapper
    allow(event_mapper).to receive(:to_record_attributes).with(test_event).and_return(
      {
        name: "test.event",
        payload: { "key" => "value" },
        source: "test-source"
      }
    )

    allow(event_mapper).to receive(:to_domain_event).with(domain_event_record).and_return(
      test_event.with_id("123")
    )

    allow(event_mapper).to receive(:event_id_to_aggregate_id).and_return(
      "00000000-0000-0000-0000-000000000000"
    )

    # Mock DomainEvent instance
    allow(DomainEvent).to receive(:new).and_return(domain_event_record)
    allow(domain_event_record).to receive(:save!).and_return(true)
    allow(DomainEvent).to receive(:create!).and_return(domain_event_record)

    # Set up event_factory double
    event_factory = class_double("Domain::EventFactory")
    allow(event_factory).to receive(:create).and_return(test_event.with_id("123"))
    stub_const("Domain::EventFactory", event_factory)

    # Set up Rails.env for testing
    rails_env = ActiveSupport::StringInquirer.new("test")
    allow(Rails).to receive(:env).and_return(rails_env)

    # Setup cache for events
    repository.instance_variable_set(:@events_cache, {})
  end

  describe "#save_event" do
    context "when successful" do
      it "saves an event to the database and returns it" do
        # Arrange
        allow(DomainEvent).to receive(:create!).and_return(domain_event_record)

        # Act
        result = repository.save_event(test_event)

        # Assert
        expect(result).to be_a(Domain::Event)
        expect(result.id).to eq("123")
        expect(result.name).to eq("test.event")
      end
    end

    context "when errors occur" do
      it "raises ArgumentError if event is nil" do
        expect { repository.save_event(nil) }.to raise_error(ArgumentError, "Event cannot be nil")
      end

      it "handles database connection errors" do
        # Arrange
        allow(domain_event_record).to receive(:save!).and_raise(ActiveRecord::ConnectionNotEstablished.new("Connection error"))

        # Act & Assert
        expect { repository.save_event(test_event) }.to raise_error(Repositories::Errors::DatabaseError) do |error|
          expect(error.context).to include(event_name: "test.event")
        end
      end

      it "handles validation errors" do
        # Arrange
        record = instance_double("DomainEvent", errors: double(full_messages: ["Name can't be blank"]))
        error = ActiveRecord::RecordInvalid.new(record)
        allow(domain_event_record).to receive(:save!).and_raise(error)

        # Act & Assert
        expect { repository.save_event(test_event) }.to raise_error(Repositories::Errors::ValidationError)
      end

      it "handles SQL errors" do
        # Arrange
        allow(domain_event_record).to receive(:save!).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))

        # Act & Assert
        expect { repository.save_event(test_event) }.to raise_error(Repositories::Errors::DatabaseError) do |error|
          expect(error.context).to include(event_name: "test.event")
        end
      end
    end
  end

  describe "#find_event" do
    context "when successful" do
      it "returns nil when id is blank" do
        # Act
        result = repository.find_event("")

        # Assert
        expect(result).to be_nil
      end

      it "returns the cached event if available" do
        # Arrange - Set up test env cache for test
        repository.instance_variable_get(:@events_cache)["123"] = test_event.with_id("123")

        # Act
        result = repository.find_event("123")

        # Assert
        expect(result).to be_a(Domain::Event)
        expect(result.id).to eq("123")
        # Ensure lookup wasn't used
        expect(lookup_strategy).not_to have_received(:find_record)
      end

      it "fetches event from database if not in cache" do
        # Arrange
        allow(lookup_strategy).to receive(:find_record).with("123").and_return(domain_event_record)

        # Act
        result = repository.find_event("123")

        # Assert
        expect(result).to be_a(Domain::Event)
        expect(result.id).to eq("123")
        expect(lookup_strategy).to have_received(:find_record).with("123")
      end

      it "returns nil if event is not found" do
        # Arrange
        allow(lookup_strategy).to receive(:find_record).with("999").and_return(nil)

        # Act
        result = repository.find_event("999")

        # Assert
        expect(result).to be_nil
      end
    end

    context "when errors occur" do
      it "handles database errors" do
        # Arrange
        allow(lookup_strategy).to receive(:find_record).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))

        # Act & Assert
        expect { repository.find_event("123") }.to raise_error(Repositories::Errors::DatabaseError) do |error|
          expect(error.context).to include(id: "123")
        end
      end
    end
  end

  describe "#append_event" do
    context "when successful" do
      it "appends an event to the database" do
        # Arrange
        allow(DomainEvent).to receive(:create!).and_return(domain_event_record)

        # Act
        result = repository.append_event(
          aggregate_id: "some-id",
          event_type: "test-event",
          payload: { key: "value" }
        )

        # Assert
        expect(result).to be_a(Domain::Event)
        expect(result.id).to eq("123")
      end
    end

    context "when errors occur" do
      it "raises ArgumentError if aggregate_id is nil" do
        expect do
          repository.append_event(
            aggregate_id: nil,
            event_type: "test-event",
            payload: { key: "value" }
          )
        end.to raise_error(ArgumentError, "Aggregate ID cannot be nil")
      end

      it "raises ArgumentError if event_type is nil" do
        expect do
          repository.append_event(
            aggregate_id: "some-id",
            event_type: nil,
            payload: { key: "value" }
          )
        end.to raise_error(ArgumentError, "Event type cannot be nil")
      end

      it "raises ArgumentError if payload is nil" do
        expect do
          repository.append_event(
            aggregate_id: "some-id",
            event_type: "test-event",
            payload: nil
          )
        end.to raise_error(ArgumentError, "Payload cannot be nil")
      end

      it "handles database errors" do
        # Arrange
        allow(DomainEvent).to receive(:create!).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))

        # Act & Assert
        expect do
          repository.append_event(
            aggregate_id: "some-id",
            event_type: "test-event",
            payload: { key: "value" }
          )
        end.to raise_error(Repositories::Errors::DatabaseError) do |error|
          expect(error.context).to include(aggregate_id: "some-id")
        end
      end
    end
  end

  describe "#read_events" do
    context "when successful" do
      it "reads events from the database" do
        # Arrange
        relation = double("ActiveRecord::Relation")
        allow(DomainEvent).to receive(:since_position).and_return(relation)
        allow(relation).to receive(:chronological).and_return(relation)
        allow(relation).to receive(:limit).and_return(relation)
        allow(relation).to receive(:map).and_yield(domain_event_record).and_return([test_event.with_id("123")])

        # Act
        result = repository.read_events(from_position: 0, limit: 10)

        # Assert
        expect(result).to be_an(Array)
        expect(result.size).to eq(1)
        expect(result.first.id).to eq("123")
      end
    end

    context "when errors occur" do
      it "handles query errors" do
        # Arrange
        allow(DomainEvent).to receive(:since_position).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))

        # Act & Assert
        expect { repository.read_events }.to raise_error(Repositories::Errors::QueryError) do |error|
          expect(error.context).to include(from_position: 0)
        end
      end
    end
  end

  describe "#read_stream" do
    context "when successful" do
      it "reads events for a specific aggregate" do
        # Arrange
        relation = double("ActiveRecord::Relation")
        allow(DomainEvent).to receive(:for_aggregate).and_return(relation)
        allow(relation).to receive(:since_position).and_return(relation)
        allow(relation).to receive(:chronological).and_return(relation)
        allow(relation).to receive(:limit).and_return(relation)
        allow(relation).to receive(:map).and_yield(domain_event_record).and_return([test_event.with_id("123")])

        # Act
        result = repository.read_stream(
          aggregate_id: "some-id",
          from_position: 0,
          limit: 10
        )

        # Assert
        expect(result).to be_an(Array)
        expect(result.size).to eq(1)
        expect(result.first.id).to eq("123")
      end
    end

    context "when errors occur" do
      it "raises ArgumentError if aggregate_id is nil" do
        expect do
          repository.read_stream(
            aggregate_id: nil
          )
        end.to raise_error(ArgumentError, "Aggregate ID cannot be nil")
      end

      it "handles query errors" do
        # Arrange
        allow(DomainEvent).to receive(:for_aggregate).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))

        # Act & Assert
        expect do
          repository.read_stream(aggregate_id: "some-id")
        end.to raise_error(Repositories::Errors::QueryError) do |error|
          expect(error.context).to include(aggregate_id: "some-id")
        end
      end
    end
  end

  describe "#cache_event" do
    before do
      # Reset to test environment
      Rails.env = ActiveSupport::StringInquirer.new("test")
    end

    it "stores event in memory cache in test environment" do
      # Act
      repository.send(:cache_event, test_event.with_id("123"))

      # Assert - use the instance variable to check the cache
      cached_event = repository.instance_variable_get(:@events_cache)["123"]
      expect(cached_event).to be_a(Domain::Event)
      expect(cached_event.id).to eq("123")
    end

    it "handles caching errors gracefully" do
      # Arrange - Create a situation where caching would fail
      repository.instance_variable_set(:@events_cache, nil)

      # Act - This should not raise an error
      result = repository.send(:cache_event, test_event.with_id("123"))

      # Assert
      expect(result).to eq(test_event.with_id("123"))
    end
  end

  describe "#get_from_cache" do
    before do
      # Reset to test environment
      Rails.env = ActiveSupport::StringInquirer.new("test")
    end

    it "returns nil for blank id" do
      # Act
      result = repository.send(:get_from_cache, "")

      # Assert
      expect(result).to be_nil
    end

    it "returns cached event if found" do
      # Arrange - add to cache
      repository.instance_variable_set(:@events_cache, { "123" => test_event.with_id("123") })

      # Act
      result = repository.send(:get_from_cache, "123")

      # Assert
      expect(result).to be_a(Domain::Event)
      expect(result.id).to eq("123")
    end

    it "handles cache retrieval errors gracefully" do
      # Arrange - Create a situation where cache retrieval would fail
      repository.instance_variable_set(:@events_cache, nil)

      # Act - This should not raise an error
      result = repository.send(:get_from_cache, "123")

      # Assert
      expect(result).to be_nil
    end
  end
end
