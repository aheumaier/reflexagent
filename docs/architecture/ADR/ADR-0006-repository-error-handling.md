# ADR-0006: Consistent Error Handling in Repositories

## Status

Accepted

## Context

In our hexagonal architecture, repositories serve as adapters between the domain layer and the database. As we've expanded our application, we've faced challenges with:

1. Inconsistent error handling across repositories
2. Leaking of infrastructure concerns (like database errors) to domain logic
3. Inadequate context in error messages
4. Inconsistent logging of repository errors

We needed a standardized approach to error handling in repositories that would:
- Provide domain-specific error types
- Include relevant context in errors
- Ensure proper logging
- Decouple infrastructure errors from domain code

## Decision

We've implemented a consistent error handling approach with these components:

1. **Create a Repository Error Hierarchy**: A dedicated set of repository-specific errors that extend from a base `MetricRepositoryError` class.

2. **Implement an `ErrorHandler` Concern**: A shared module that all repositories include, providing standardized methods for handling different error scenarios.

3. **Use Context-Rich Errors**: All errors include relevant context (like operation type, metric ID, etc.) to aid debugging.

4. **Integrate with Logger Port**: All error handling is integrated with the application's logger port to ensure consistent logging.

5. **Input Validation Methods**: Standardized methods for validating inputs before operations.

## Error Types

Our error hierarchy includes:

- `MetricRepositoryError`: Base class for all repository errors
  - `DatabaseError`: For database operation failures
  - `ValidationError`: For input validation failures
    - `InvalidMetricNameError`: For metrics with invalid names
    - `InvalidDimensionError`: For invalid dimension values
  - `QueryError`: For query construction/execution errors
  - `NotFoundError`: For "not found" scenarios
  - `UnsupportedOperationError`: For operations not supported by a repository type

## Implementation Details

### The ErrorHandler Concern

The `ErrorHandler` concern provides methods for:

- `handle_database_error`: Managing database exceptions
- `handle_not_found`: Handling missing records
- `handle_query_error`: Managing query failures
- `validate_metric`: Validating metric structure
- `validate_dimensions`: Validating dimension structure
- `handle_unsupported_operation`: Handling unsupported operations

### Usage Pattern

Repositories should:

```ruby
class SomeRepository
  include Repositories::Concerns::ErrorHandler
  
  def some_operation(input)
    validate_input(input)
    
    handle_database_error("some_operation", { context: "details" }) do
      # Database operation here
    end
  rescue SomeSpecificError => e
    handle_specific_error(e, { context: "details" })
  end
end
```

## Consequences

### Positive

- Domain code is protected from infrastructure implementation details
- Consistent error information across repositories
- Improved debuggability through context-rich errors
- Consistent logging of repository errors
- Cleaner repository implementations with less error-handling boilerplate

### Negative

- Additional code to maintain in the error handler
- Need to ensure all repositories use the error handler consistently
- May require updates if error handling requirements change

## Implementation Notes

1. All repositories should include the `ErrorHandler` concern
2. All repository methods should use the appropriate error handler methods
3. Tests should verify error handling works as expected
4. Errors should include enough context to debug issues

## References

- [Repository Architecture](../repository_architecture.md)
- [Hexagonal Architecture Principles](../README.md) 