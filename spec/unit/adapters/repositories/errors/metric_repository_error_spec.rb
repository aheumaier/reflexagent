# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repositories::Errors::MetricRepositoryError do
  describe "base error class" do
    it "stores the source error and context" do
      source_error = StandardError.new("Original error")
      context = { repository: "test_repo" }
      error = described_class.new("Test error message", source_error, context)

      expect(error.message).to eq("Test error message")
      expect(error.source_error).to eq(source_error)
      expect(error.context).to eq(context)
    end

    it "has nil source_error when none is provided" do
      error = described_class.new("Test error message")
      expect(error.source_error).to be_nil
    end

    it "has empty context when none is provided" do
      error = described_class.new("Test error message")
      expect(error.context).to eq({})
    end

    describe "#root_cause" do
      it "returns self when there is no source error" do
        error = described_class.new("Test error message")
        expect(error.root_cause).to eq(error)
      end

      it "returns the source error when present" do
        source_error = StandardError.new("Root cause")
        error = described_class.new("Test error message", source_error)
        expect(error.root_cause).to eq(source_error)
      end

      it "returns nested source error when present" do
        root_error = StandardError.new("Root cause")
        middle_error = StandardError.new("Middle error")
        allow(middle_error).to receive(:cause).and_return(root_error)

        error = described_class.new("Test error message", middle_error)
        expect(error.root_cause).to eq(root_error)
      end
    end

    describe "#full_backtrace" do
      it "includes both error and source error backtraces" do
        source_error = StandardError.new("Original error")
        allow(source_error).to receive(:backtrace).and_return(["source:1", "source:2"])

        error = described_class.new("Test error message", source_error)
        allow(error).to receive(:backtrace).and_return(["error:1", "error:2"])

        full_trace = error.full_backtrace
        expect(full_trace).to include("error:1", "error:2")
        expect(full_trace).to include("source:1", "source:2")
      end
    end
  end

  describe Repositories::Errors::MetricNotFoundError do
    it "formats error message with ID" do
      error = described_class.new("123")
      expect(error.message).to eq("Metric not found with ID: 123")
      expect(error.context[:id]).to eq("123")
    end
  end

  describe Repositories::Errors::DatabaseError do
    it "formats error message with operation" do
      error = described_class.new("save")
      expect(error.message).to eq("Database error during save")
      expect(error.context[:operation]).to eq("save")
    end

    it "formats message specifically for record not found errors" do
      source_error = ActiveRecord::RecordNotFound.new("Record not found")
      error = described_class.new("find", source_error)

      expect(error.message).to eq("Record not found during find")
      expect(error.source_error).to eq(source_error)
    end

    it "formats message specifically for SQL errors" do
      source_error = ActiveRecord::StatementInvalid.new("SQL syntax error")
      error = described_class.new("query", source_error)

      expect(error.message).to eq("SQL error during query")
      expect(error.source_error).to eq(source_error)
    end
  end

  describe Repositories::Errors::ValidationError do
    it "creates error with custom message" do
      error = described_class.new("Invalid metric value", { metric_name: "test.metric" })

      expect(error.message).to eq("Invalid metric value")
      expect(error.context[:metric_name]).to eq("test.metric")
    end
  end

  describe Repositories::Errors::InvalidMetricNameError do
    it "formats error message with metric name" do
      error = described_class.new("invalid.name")
      expect(error.message).to eq("Invalid metric name: invalid.name")
      expect(error.context[:metric_name]).to eq("invalid.name")
    end
  end

  describe Repositories::Errors::InvalidDimensionError do
    it "formats error message with dimension name and value" do
      error = described_class.new("repository", nil)
      expect(error.message).to eq("Invalid dimension: repository = nil")
      expect(error.context[:dimension_name]).to eq("repository")
      expect(error.context[:dimension_value]).to be_nil
    end

    it "properly formats complex values" do
      value = { key: "value" }
      error = described_class.new("data", value)
      expect(error.message).to eq("Invalid dimension: data = {:key=>\"value\"}")
      expect(error.context[:dimension_value]).to eq(value)
    end
  end

  describe Repositories::Errors::QueryError do
    it "formats message for ActiveRecord errors" do
      source_error = ActiveRecord::StatementInvalid.new("SQL syntax error")
      error = described_class.new("metrics search", source_error)

      expect(error.message).to eq("Error executing metrics search query")
      expect(error.context[:query_type]).to eq("metrics search")
    end

    it "formats message for other errors" do
      source_error = StandardError.new("Unknown error")
      error = described_class.new("metrics search", source_error)

      expect(error.message).to eq("Unexpected query error in metrics search")
      expect(error.context[:query_type]).to eq("metrics search")
    end
  end

  describe Repositories::Errors::UnsupportedOperationError do
    it "formats error message with operation name" do
      error = described_class.new("complex_query")
      expect(error.message).to eq("Operation not supported: complex_query")
      expect(error.context[:operation]).to eq("complex_query")
    end
  end
end
