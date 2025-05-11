# frozen_string_literal: true

module Repositories
  module Errors
    # Base class for all repository errors
    class MetricRepositoryError < StandardError
      attr_reader :source_error, :context

      # Initialize a new repository error
      # @param message [String] The error message
      # @param source_error [Exception, nil] The original error that caused this error
      # @param context [Hash] Additional context information about the error
      def initialize(message = nil, source_error = nil, context = {})
        @source_error = source_error
        @context = context || {}

        # Use the plain message without context or source error details
        # This makes error messages cleaner and more predictable in tests
        super(message || "Repository error occurred")
      end

      # Returns the root cause of this error (traversing through source errors)
      # @return [Exception] The original exception that started the chain
      def root_cause
        if source_error
          if source_error.respond_to?(:cause) && source_error.cause
            source_error.cause
          elsif source_error.respond_to?(:source_error) && source_error.source_error
            source_error.source_error
          else
            source_error
          end
        else
          self
        end
      end

      # Returns the full backtrace combining this error and all source errors
      # @return [Array<String>] The combined backtrace
      def full_backtrace
        traces = []
        traces.concat(backtrace) if backtrace

        # Follow both cause and source_error chains
        current = source_error
        while current
          traces.concat(current.backtrace) if current.respond_to?(:backtrace) && current.backtrace

          # Try both cause and source_error for next error in chain
          current = if current.respond_to?(:cause) && current.cause
                      current.cause
                    elsif current.respond_to?(:source_error) && current.source_error
                      current.source_error
                    else
                      nil
                    end
        end

        traces.uniq
      end
    end

    # Error raised when a metric is not found
    class MetricNotFoundError < MetricRepositoryError
      # @param id [String, Integer] The ID that was not found
      # @param source_error [Exception, nil] The original error
      # @param context [Hash] Additional context
      def initialize(id, source_error = nil, context = {})
        super("Metric not found with ID: #{id}", source_error, context.merge(id: id))
      end
    end

    # Error raised for database operations
    class DatabaseError < MetricRepositoryError
      # @param operation [String] The operation that failed
      # @param source_error [Exception, nil] The original error
      # @param context [Hash] Additional context
      def initialize(operation, source_error = nil, context = {})
        message = "Database error during #{operation}"

        # Add more specific details for common ActiveRecord errors
        if source_error
          if source_error.is_a?(ActiveRecord::RecordNotFound)
            message = "Record not found during #{operation}"
          elsif source_error.is_a?(ActiveRecord::RecordInvalid) && source_error.respond_to?(:record)
            # Include validation errors if available
            message = "Validation failed during #{operation}: #{source_error.record.errors.full_messages.join(', ')}"
          elsif source_error.is_a?(ActiveRecord::StatementInvalid)
            message = "SQL error during #{operation}"
          elsif source_error.is_a?(ActiveRecord::ConnectionNotEstablished)
            message = "Database connection error during #{operation}"
          end
        end

        super(message, source_error, context.merge(operation: operation))
      end
    end

    # Error raised for validation failures
    class ValidationError < MetricRepositoryError
      # @param message [String] The validation message
      # @param context [Hash] Additional context
      def initialize(message, context = {})
        super(message, nil, context)
      end
    end

    # Error raised for invalid metric names
    class InvalidMetricNameError < MetricRepositoryError
      # @param name [String] The invalid metric name
      # @param context [Hash] Additional context
      def initialize(name, context = {})
        super("Invalid metric name: #{name}", nil, context.merge(metric_name: name))
      end
    end

    # Error raised for invalid dimension values
    class InvalidDimensionError < MetricRepositoryError
      # @param name [String] The dimension name
      # @param value [Object] The dimension value
      # @param context [Hash] Additional context
      def initialize(name, value, context = {})
        super("Invalid dimension: #{name} = #{value.inspect}", nil,
              context.merge(dimension_name: name, dimension_value: value))
      end
    end

    # Error raised for query errors
    class QueryError < MetricRepositoryError
      # @param query_type [String] The type of query that failed
      # @param source_error [Exception, nil] The original error
      # @param context [Hash] Additional context
      def initialize(query_type, source_error = nil, context = {})
        # Create the appropriate message based on the error type
        message = if source_error && source_error.is_a?(ActiveRecord::StatementInvalid)
                    "Error executing #{query_type} query"
                  else
                    "Unexpected query error in #{query_type}"
                  end

        super(message, source_error, context.merge(query_type: query_type))
      end
    end

    # Error raised for unsupported operations
    class UnsupportedOperationError < MetricRepositoryError
      # @param operation [String] The unsupported operation
      # @param context [Hash] Additional context
      def initialize(operation, context = {})
        super("Operation not supported: #{operation}", nil, context.merge(operation: operation))
      end
    end
  end
end
