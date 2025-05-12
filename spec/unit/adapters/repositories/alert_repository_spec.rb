# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repositories::AlertRepository do
  let(:logger) { instance_double("Logger", debug: nil, info: nil, warn: nil, error: nil) }
  let(:repository) { described_class.new(logger_port: logger) }

  let(:test_metric) do
    instance_double(
      Domain::Metric,
      id: "metric-123",
      name: "test.metric",
      value: 95.0,
      source: "test-source",
      dimensions: {},
      timestamp: Time.current,
      is_a?: true
    )
  end

  let(:test_alert) do
    alert = Domain::Alert.new(
      name: "test_alert",
      severity: :critical,
      metric: test_metric,
      threshold: 90.0,
      timestamp: Time.current,
      status: :active
    )

    # Allow with_id to return a new mock with any ID
    allow(alert).to receive(:with_id) do |id|
      Domain::Alert.new(
        id: id,
        name: "test_alert",
        severity: :critical,
        metric: test_metric,
        threshold: 90.0,
        timestamp: Time.current,
        status: :active
      )
    end

    alert
  end

  let(:domain_alert_record) do
    instance_double(
      "DomainAlert",
      id: 123,
      name: "test_alert",
      severity: "critical",
      status: "active",
      threshold: 90.0,
      timestamp: Time.current,
      to_domain_model: test_alert.with_id("123"),
      update!: true
    )
  end

  let(:alert_record_1) do
    instance_double(
      "DomainAlert",
      id: 1,
      name: "alert_1",
      severity: "warning",
      status: "active",
      to_domain_model: Domain::Alert.new(
        id: "1",
        name: "alert_1",
        severity: :warning,
        metric: test_metric,
        threshold: 90.0,
        status: :active
      )
    )
  end

  let(:alert_record_2) do
    instance_double(
      "DomainAlert",
      id: 2,
      name: "alert_2",
      severity: "critical",
      status: "active",
      to_domain_model: Domain::Alert.new(
        id: "2",
        name: "alert_2",
        severity: :critical,
        metric: test_metric,
        threshold: 90.0,
        status: :active
      )
    )
  end

  # Setup ActiveRecord mocks
  before do
    # Configure the logger to be correctly called
    allow(logger).to receive(:error).with(any_args)
    allow(logger).to receive(:error) { |&block| block.call if block }

    # Make test_metric behave like a Domain::Metric
    allow(test_metric).to receive(:is_a?).with(Domain::Metric).and_return(true)

    # Allow to_domain_model to work on domain_alert_record
    allow(domain_alert_record).to receive(:to_domain_model).and_return(
      test_alert.with_id("123")
    )

    # Clear the alerts cache between tests
    repository.instance_variable_set(:@alerts_cache, {})

    # Setup DomainAlert stub with required class methods
    domain_alert_class = Class.new do
      def self.find_by(*)
        nil
      end

      def self.all
        []
      end

      def self.create!(*)
        nil
      end

      def self.where(*)
        nil
      end

      def self.by_severity(*)
        nil
      end
    end

    # Create or reassign the constants
    if defined?(DomainAlert)
      stub_const("DomainAlert", domain_alert_class)
    else
      Object.const_set("DomainAlert", domain_alert_class)
    end

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

    # Set up Rails.env for testing
    rails_env = ActiveSupport::StringInquirer.new("test")
    allow(Rails).to receive(:env).and_return(rails_env)
  end

  describe "#save_alert" do
    context "when successful" do
      it "saves an alert to the database and returns the saved object" do
        # Arrange
        allow(DomainAlert).to receive(:find_by).and_return(nil)
        allow(DomainAlert).to receive(:create!).and_return(domain_alert_record)

        # Act
        result = repository.save_alert(test_alert)

        # Assert
        expect(result).to be_a(Domain::Alert)
        expect(result.id).to eq("123")
        expect(result.name).to eq("test_alert")
      end

      it "updates an existing alert if it exists" do
        # Arrange
        existing_alert = test_alert.with_id("123")
        allow(DomainAlert).to receive(:find_by).and_return(domain_alert_record)
        allow(domain_alert_record).to receive(:update!).and_return(true)

        # Act
        result = repository.save_alert(existing_alert)

        # Assert
        expect(domain_alert_record).to have_received(:update!)
        expect(result.id).to eq("123")
      end
    end

    context "when errors occur" do
      it "raises ArgumentError if alert is nil" do
        expect { repository.save_alert(nil) }.to raise_error(ArgumentError, "Alert cannot be nil")
      end

      it "handles database connection errors" do
        # Arrange
        allow(DomainAlert).to receive(:find_by).and_raise(ActiveRecord::ConnectionNotEstablished.new("Connection error"))

        # Act & Assert
        expect { repository.save_alert(test_alert) }.to raise_error(Repositories::Errors::DatabaseError) do |error|
          expect(error.context).to include(alert_name: "test_alert")
        end
      end

      it "handles validation errors" do
        # Arrange
        record = instance_double("DomainAlert", errors: double(full_messages: ["Name can't be blank"]))
        error = ActiveRecord::RecordInvalid.new(record)
        allow(DomainAlert).to receive(:find_by).and_return(nil)
        allow(DomainAlert).to receive(:create!).and_raise(error)

        # Act & Assert
        expect { repository.save_alert(test_alert) }.to raise_error(Repositories::Errors::ValidationError)
      end

      it "handles general database errors" do
        # Arrange
        allow(DomainAlert).to receive(:find_by).and_return(nil)
        allow(DomainAlert).to receive(:create!).and_raise(StandardError.new("Unknown error"))

        # Act & Assert
        expect { repository.save_alert(test_alert) }.to raise_error(Repositories::Errors::DatabaseError) do |error|
          expect(error.context).to include(alert_name: "test_alert")
        end
      end
    end
  end

  describe "#find_alert" do
    context "when successful" do
      it "returns nil if id is nil" do
        expect(repository.find_alert(nil)).to be_nil
      end

      it "returns an alert from cache if available" do
        # Arrange - add to cache
        cached_alert = test_alert.with_id("123")
        repository.instance_variable_get(:@alerts_cache)["123"] = cached_alert
        allow(DomainAlert).to receive(:find_by)

        # Act
        result = repository.find_alert("123")

        # Assert
        expect(result).to eq(cached_alert)
        expect(DomainAlert).not_to have_received(:find_by)
      end

      it "fetches an alert from the database if not in cache" do
        # Arrange
        allow(DomainAlert).to receive(:find_by).with(id: "123").and_return(domain_alert_record)

        # Act
        result = repository.find_alert("123")

        # Assert
        expect(result).to be_a(Domain::Alert)
        expect(result.id).to eq("123")
      end

      it "returns nil if alert not found in database" do
        # Arrange
        allow(DomainAlert).to receive(:find_by).with(id: "999").and_return(nil)

        # Act
        result = repository.find_alert("999")

        # Assert
        expect(result).to be_nil
      end
    end

    context "when errors occur" do
      it "handles database errors" do
        # Arrange
        allow(DomainAlert).to receive(:find_by).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))

        # Act & Assert
        expect { repository.find_alert("123") }.to raise_error(Repositories::Errors::DatabaseError) do |error|
          expect(error.context).to include(id: "123")
        end
      end
    end
  end

  describe "#list_alerts" do
    context "when successful" do
      it "returns a list of alerts with filters applied" do
        # Arrange
        relation = double("ActiveRecord::Relation")
        allow(DomainAlert).to receive(:all).and_return(relation)
        allow(relation).to receive(:where).and_return(relation)
        allow(relation).to receive(:by_severity).and_return(relation)
        allow(relation).to receive(:limit).and_return(relation)
        allow(relation).to receive(:order).and_return([alert_record_1, alert_record_2])

        # Act
        result = repository.list_alerts(
          status: :active,
          severity: :critical,
          limit: 10,
          latest_first: true
        )

        # Assert
        expect(result.size).to eq(2)
        expect(result.first.name).to eq("alert_1")
        expect(result.last.name).to eq("alert_2")
      end
    end

    context "when errors occur" do
      it "handles query errors" do
        # Arrange
        allow(DomainAlert).to receive(:all).and_raise(ActiveRecord::StatementInvalid.new("SQL syntax error"))

        # Act & Assert
        expect { repository.list_alerts(status: :active) }.to raise_error(Repositories::Errors::QueryError) do |error|
          expect(error.context).to include(filters: { status: :active })
        end
      end

      it "handles unexpected errors" do
        # Arrange
        allow(DomainAlert).to receive(:all).and_raise(StandardError.new("Unexpected error"))

        # Act & Assert
        expect { repository.list_alerts }.to raise_error(Repositories::Errors::QueryError)
      end
    end
  end
end
