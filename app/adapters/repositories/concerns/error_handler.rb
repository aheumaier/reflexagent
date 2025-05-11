# frozen_string_literal: true

require_relative "../errors/metric_repository_error"

module Repositories
  module Concerns
    # ErrorHandler provides consistent error handling for metric repositories
    # It includes methods to handle common errors, validate inputs, and log errors
    module ErrorHandler
      # Handle database operation errors
      # @param operation [String] The database operation being performed
      # @param context [Hash] Additional context for the error
      # @yield The database operation to execute
      # @return [Object] The result of the block if successful
      # @raise [DatabaseError] If a database error occurs
      def handle_database_error(operation, context = {})
        yield
      rescue ActiveRecord::RecordNotFound => e
        log_error("Record not found during #{operation}: #{e.message}")
        raise Repositories::Errors::MetricNotFoundError.new(context[:id] || "unknown", e, context)
      rescue ActiveRecord::RecordInvalid => e
        log_error("Validation error during #{operation}: #{e.message}")
        raise Repositories::Errors::ValidationError.new(
          "Validation failed during #{operation}: #{e.message}",
          context.merge(operation: operation)
        )
      rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished,
             PG::Error => e
        log_error("Database error during #{operation}: #{e.message}")
        raise Repositories::Errors::DatabaseError.new(operation, e, context)
      rescue StandardError => e
        log_error("Unexpected error during #{operation}: #{e.message}")
        raise Repositories::Errors::DatabaseError.new(operation, e, context)
      end

      # Handle not found errors
      # @param id [String, Integer] The ID that was not found
      # @param context [Hash] Additional context for the error
      # @raise [MetricNotFoundError] With the ID and context
      def handle_not_found(id, context = {})
        log_warn("Metric not found with ID: #{id}")
        raise Repositories::Errors::MetricNotFoundError.new(id, nil, context)
      end

      # Handle query errors
      # @param query_type [String] The type of query being executed
      # @param context [Hash] Additional context for the error
      # @yield The query operation to execute
      # @return [Object] The result of the block if successful
      # @raise [QueryError] If a query error occurs
      def handle_query_error(query_type, context = {})
        yield
      rescue ActiveRecord::StatementInvalid, PG::Error => e
        log_error("Error in #{query_type} query: #{e.message}")
        raise Repositories::Errors::QueryError.new(query_type, e, context)
      rescue StandardError => e
        log_error("Unexpected error in #{query_type} query: #{e.message}")
        raise Repositories::Errors::QueryError.new(query_type, e, context)
      end

      # Validate that the provided object is a metric
      # @param metric [Object] The object to validate
      # @param context [Hash] Additional context for the error
      # @return [Boolean] true if the metric is valid
      # @raise [ValidationError] If the metric is invalid
      def validate_metric(metric, context = {})
        unless metric.is_a?(Domain::Metric)
          error_context = context.merge(actual_class: metric&.class)
          log_error("Invalid metric type: expected Domain::Metric, got #{metric&.class}")
          raise Repositories::Errors::ValidationError.new(
            "Invalid metric type: #{metric&.class}",
            error_context
          )
        end

        # Validate metric name if we have a metric_naming_port
        if respond_to?(:metric_naming_port) && metric_naming_port &&
           metric_naming_port.respond_to?(:valid_metric_name?) && !metric_naming_port.valid_metric_name?(metric.name)
          error_context = context.merge(metric_name: metric.name)
          log_error("Invalid metric name: #{metric.name}")
          raise Repositories::Errors::InvalidMetricNameError.new(metric.name, error_context)
        end

        true
      end

      # Validate the dimensions hash
      # @param dimensions [Hash, nil] The dimensions hash to validate
      # @param context [Hash] Additional context for the error
      # @return [Boolean] true if dimensions are valid
      # @raise [ValidationError] If dimensions are invalid
      # @raise [InvalidDimensionError] If a specific dimension is invalid
      def validate_dimensions(dimensions, context = {})
        # Nil or empty dimensions are valid
        return true if dimensions.nil? || dimensions.empty?

        # Dimensions must be a Hash
        unless dimensions.is_a?(Hash)
          error_context = context.merge(actual_class: dimensions.class)
          log_error("Invalid dimensions type: expected Hash, got #{dimensions.class}")
          raise Repositories::Errors::ValidationError.new(
            "Dimensions must be a hash",
            error_context
          )
        end

        # Validate each dimension
        dimensions.each do |key, value|
          # Key can't be nil or empty
          if key.nil?
            error_context = context.merge(dimension_value: value)
            log_error("Invalid dimension: nil key")
            raise Repositories::Errors::InvalidDimensionError.new("", value, error_context)
          end

          # Key can't be an empty string
          if key.is_a?(String) && key.empty?
            error_context = context.merge(dimension_value: value)
            log_error("Invalid dimension: empty key")
            raise Repositories::Errors::InvalidDimensionError.new("", value, error_context)
          end

          # Validate dimension name and value if we have a metric_naming_port
          next unless respond_to?(:metric_naming_port) && metric_naming_port &&
                      metric_naming_port.respond_to?(:valid_dimension_name?)

          next if metric_naming_port.valid_dimension_name?(key.to_s)

          error_context = context.merge(dimension_name: key, dimension_value: value)
          log_error("Invalid dimension name: #{key}")
          raise Repositories::Errors::InvalidDimensionError.new(key, value, error_context)
        end

        true
      end

      # Handle unsupported operations
      # @param operation [String] The unsupported operation
      # @param context [Hash] Additional context for the error
      # @raise [UnsupportedOperationError] With the operation and context
      def handle_unsupported_operation(operation, context = {})
        log_error("Unsupported operation: #{operation}")
        raise Repositories::Errors::UnsupportedOperationError.new(operation, context)
      end

      # Log an error message with optional exception details
      # @param message [String] The error message
      # @param exception [Exception, nil] The exception that caused the error
      private def log_error(message, exception = nil)
        return unless respond_to?(:logger_port) && logger_port && logger_port.respond_to?(:error)

        log_message = message.dup
        log_message << ": #{exception.message}" if exception && exception.message

        # Determine if the logger uses block-style or direct-style logging
        if block_style_logging?(:error)
          # Block-style logging
          logger_port.error { log_message }
          logger_port.error { exception.backtrace.join("\n") } if exception && exception.backtrace
        else
          # Direct logging
          logger_port.error(log_message)
          logger_port.error(exception.backtrace.join("\n")) if exception && exception.backtrace
        end
      end

      # Log a warning message
      # @param message [String] The warning message
      private def log_warn(message)
        return unless respond_to?(:logger_port) && logger_port && logger_port.respond_to?(:warn)

        if block_style_logging?(:warn)
          # Block-style logging
          logger_port.warn { message }
        else
          # Direct logging
          logger_port.warn(message)
        end
      end

      # Helper to determine if a logger method uses block-style or direct-style logging
      # @param method_name [Symbol] The logger method to check
      # @return [Boolean] true if the method uses block-style logging
      private def block_style_logging?(method_name)
        return false unless respond_to?(:logger_port) && logger_port
        return false unless logger_port.respond_to?(method_name)

        # A method with arity 0 or -1 (unlimited args) might accept a block
        arity = logger_port.method(method_name).arity
        arity.zero? || arity == -1
      end
    end
  end
end
