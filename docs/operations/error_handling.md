# Repository Error Handling System

This document describes the standardized error handling system implemented in the metric repositories.

## Overview

The repository error handling system provides consistent error handling across all metric repositories. It consists of:

1. A hierarchy of error classes for different types of errors
2. A shared concern for handling errors consistently
3. Integration with the application's logging system

## Error Classes

All repository errors inherit from the base `Repositories::Errors::MetricRepositoryError` class, which provides common functionality:

- Storing the original source error (if any)
- Storing contextual information about the error
- Retrieving the root cause of an error chain
- Combining backtraces for better debugging

Specialized error classes include:

- `MetricNotFoundError` - When a metric can't be found by ID or criteria
- `DatabaseError` - Generic database operation failures
- `ValidationError` - Validation failures on metrics or parameters
- `InvalidMetricNameError` - Specifically for invalid metric names
- `InvalidDimensionError` - Specifically for invalid dimension values
- `QueryError` - For query execution errors
- `UnsupportedOperationError` - For operations not supported by a repository

## Error Handler Concern

The `Repositories::Concerns::ErrorHandler` module provides methods for consistent error handling:

- `handle_database_error` - Wraps database operations and handles ActiveRecord errors
- `handle_not_found` - Creates standardized "not found" errors
- `handle_query_error` - Wraps query operations with error handling
- `validate_metric` - Validates metrics before operations
- `validate_dimensions` - Validates dimension maps
- `handle_unsupported_operation` - For operations not supported by a repository

## Usage Pattern

Repositories should include the `ErrorHandler` concern and use its methods to handle errors:

```ruby
class MyMetricRepository
  include Repositories::Concerns::ErrorHandler
  
  def find_metric(id)
    begin
      # Database operation...
    rescue ActiveRecord::RecordNotFound
      handle_not_found(id)
    rescue => e
      handle_database_error("find", e)
    end
  end
end
```

## Error Context

Errors include context information to help with debugging:

```ruby
begin
  repository.find_metric("invalid-id")
rescue Repositories::Errors::MetricNotFoundError => e
  # e.context contains relevant information
  # e.source_error contains the original error
  # e.full_backtrace provides a combined backtrace
end
```

## Logging Integration

The error handler integrates with the application's logging system:

- Errors are logged at appropriate levels (error, warn)
- Log messages include the operation context and source error details
- Backtraces are included for critical errors

## Best Practices

1. Always use the appropriate error handling method rather than raising errors directly
2. Include relevant context when handling errors
3. Handle specific error types first, then catch general errors
4. Use the built-in validation methods before performing operations
5. Ensure error messages are clear and helpful for debugging

## Future Improvements

- Adding more specialized error types for specific operations
- Improving error reporting and monitoring integration
- Enhancing test coverage for error handling paths 