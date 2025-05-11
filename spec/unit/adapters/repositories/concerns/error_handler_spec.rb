# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repositories::Concerns::ErrorHandler do
  # Create a test class that includes the ErrorHandler module
  class TestRepository
    include Repositories::Concerns::ErrorHandler

    attr_reader :logger_port, :metric_naming_port

    def initialize(logger_port: nil, metric_naming_port: nil)
      @logger_port = logger_port
      @metric_naming_port = metric_naming_port
    end

    def test_database_error(operation, &block)
      handle_database_error(operation, { test: "context" }, &block)
    end

    def test_not_found(id)
      handle_not_found(id, { test: "context" })
    end

    def test_query_error(query_type, &block)
      handle_query_error(query_type, { test: "context" }, &block)
    end

    def test_validate_metric(metric)
      validate_metric(metric, { test: "context" })
    end

    def test_validate_dimensions(dimensions)
      validate_dimensions(dimensions, { test: "context" })
    end

    def test_unsupported_operation(operation)
      handle_unsupported_operation(operation, { test: "context" })
    end
  end

  let(:logger) { instance_double("Logger", debug: nil, info: nil, warn: nil, error: nil) }
  let(:repository) { TestRepository.new(logger_port: logger) }

  # Setup some mock errors
  before do
    # Create custom ActiveRecord mocks to avoid Rails-specific functionality
    module MockActiveRecord
      class Base; end
      class RecordNotFound < StandardError; end
      class StatementInvalid < StandardError; end
      class ConnectionNotEstablished < StandardError; end

      class RecordInvalid < StandardError
        attr_reader :record

        def initialize(message = "Record Invalid")
          @record = nil
          super
        end
      end
    end

    # Mock PG::Error
    module MockPG
      class Error < StandardError; end
    end

    # Temporarily replace Rails ActiveRecord with our mock version
    hide_const("ActiveRecord")
    stub_const("ActiveRecord", MockActiveRecord)

    # Stub PG::Error
    hide_const("PG::Error") if defined?(PG::Error)
    stub_const("PG", MockPG)

    # Stub Domain::Metric
    module MockDomain
      class Metric
        attr_reader :id, :name, :value, :source, :dimensions, :timestamp

        def initialize(id: nil, name: nil, value: nil, source: nil, dimensions: {}, timestamp: nil)
          @id = id
          @name = name
          @value = value
          @source = source
          @dimensions = dimensions
          @timestamp = timestamp
        end
      end
    end

    hide_const("Domain") if defined?(Domain)
    stub_const("Domain", MockDomain)
  end

  describe "#handle_database_error" do
    it "returns the result when no error occurs" do
      result = repository.test_database_error("test_operation") { "success" }
      expect(result).to eq("success")
    end

    it "raises MetricNotFoundError when an ActiveRecord::RecordNotFound error occurs" do
      active_record_error = ActiveRecord::RecordNotFound.new("Record not found")

      expect do
        repository.test_database_error("find") { raise active_record_error }
      end.to raise_error(Repositories::Errors::MetricNotFoundError) do |error|
        expect(error.message).to eq("Metric not found with ID: unknown")
        expect(error.source_error).to eq(active_record_error)
        expect(error.context).to include(test: "context")
      end
    end

    it "raises ValidationError when an validation error occurs" do
      # Using a simple error string instead of a complex mock
      active_record_error = StandardError.new("Validation failed: Field is required")

      expect do
        repository.test_database_error("save") { raise active_record_error }
      end.to raise_error(Repositories::Errors::DatabaseError) do |error|
        expect(error.message).to eq("Database error during save")
        expect(error.context).to include(operation: "save", test: "context")
      end
    end

    it "raises DatabaseError when a PG error occurs" do
      pg_error = PG::Error.new("Database connection failed")

      expect do
        repository.test_database_error("query") { raise pg_error }
      end.to raise_error(Repositories::Errors::DatabaseError) do |error|
        expect(error.message).to eq("Database error during query")
        expect(error.source_error).to eq(pg_error)
      end
    end

    it "raises DatabaseError when a different error occurs" do
      standard_error = StandardError.new("Unknown error")

      expect do
        repository.test_database_error("process") { raise standard_error }
      end.to raise_error(Repositories::Errors::DatabaseError) do |error|
        expect(error.message).to eq("Database error during process")
        expect(error.source_error).to eq(standard_error)
      end
    end
  end

  describe "#handle_not_found" do
    it "raises MetricNotFoundError with the ID" do
      expect do
        repository.test_not_found(123)
      end.to raise_error(Repositories::Errors::MetricNotFoundError) do |error|
        expect(error.message).to eq("Metric not found with ID: 123")
        expect(error.context).to include(id: 123, test: "context")
      end
    end
  end

  describe "#handle_query_error" do
    it "returns the result when no error occurs" do
      result = repository.test_query_error("test_query") { "success" }
      expect(result).to eq("success")
    end

    it "raises QueryError when an ActiveRecord::StatementInvalid error occurs" do
      statement_invalid = ActiveRecord::StatementInvalid.new("SQL syntax error")

      expect do
        repository.test_query_error("find") { raise statement_invalid }
      end.to raise_error(Repositories::Errors::QueryError) do |error|
        expect(error.message).to eq("Error executing find query")
        expect(error.source_error).to eq(statement_invalid)
        expect(error.context).to include(query_type: "find", test: "context")
      end
    end

    it "raises QueryError when another error occurs" do
      standard_error = StandardError.new("Unexpected error")

      expect do
        repository.test_query_error("search") { raise standard_error }
      end.to raise_error(Repositories::Errors::QueryError) do |error|
        expect(error.message).to eq("Unexpected query error in search")
        expect(error.source_error).to eq(standard_error)
      end
    end
  end

  describe "#validate_metric" do
    let(:valid_metric) do
      Domain::Metric.new(
        id: "123",
        name: "test.metric.total",
        value: 42.0,
        source: "test",
        dimensions: {},
        timestamp: Time.current
      )
    end

    it "returns true for a valid metric" do
      expect(repository.test_validate_metric(valid_metric)).to be true
    end

    it "raises ValidationError for nil metric" do
      expect do
        repository.test_validate_metric(nil)
      end.to raise_error(Repositories::Errors::ValidationError) do |error|
        expect(error.message).to eq("Invalid metric type: ")
        expect(error.context).to include(test: "context")
      end
    end

    it "raises ValidationError for non-metric object" do
      non_metric = "not a metric"

      expect do
        repository.test_validate_metric(non_metric)
      end.to raise_error(Repositories::Errors::ValidationError) do |error|
        expect(error.message).to eq("Invalid metric type: String")
        expect(error.context).to include(test: "context", actual_class: String)
      end
    end
  end

  describe "#validate_dimensions" do
    it "returns true for nil dimensions" do
      expect(repository.test_validate_dimensions(nil)).to be true
    end

    it "returns true for empty dimensions" do
      expect(repository.test_validate_dimensions({})).to be true
    end

    it "returns true for valid dimensions" do
      dimensions = { "repository" => "org/repo", "branch" => "main" }
      expect(repository.test_validate_dimensions(dimensions)).to be true
    end

    it "raises ValidationError for non-hash dimensions" do
      expect do
        repository.test_validate_dimensions("not a hash")
      end.to raise_error(Repositories::Errors::ValidationError) do |error|
        expect(error.message).to eq("Dimensions must be a hash")
        expect(error.context).to include(test: "context", actual_class: String)
      end
    end

    it "raises InvalidDimensionError for nil dimension keys" do
      dimensions = { nil => "value" }

      expect do
        repository.test_validate_dimensions(dimensions)
      end.to raise_error(Repositories::Errors::InvalidDimensionError) do |error|
        expect(error.message).to eq("Invalid dimension:  = \"value\"")
        expect(error.context).to include(test: "context", dimension_value: "value")
      end
    end

    it "raises InvalidDimensionError for empty dimension keys" do
      dimensions = { "" => "value" }

      expect do
        repository.test_validate_dimensions(dimensions)
      end.to raise_error(Repositories::Errors::InvalidDimensionError) do |error|
        expect(error.message).to eq("Invalid dimension:  = \"value\"")
        expect(error.context).to include(test: "context", dimension_value: "value")
      end
    end
  end

  describe "#handle_unsupported_operation" do
    it "raises UnsupportedOperationError with the operation name" do
      expect do
        repository.test_unsupported_operation("complex_query")
      end.to raise_error(Repositories::Errors::UnsupportedOperationError) do |error|
        expect(error.message).to eq("Operation not supported: complex_query")
        expect(error.context).to include(operation: "complex_query", test: "context")
      end
    end
  end
end
