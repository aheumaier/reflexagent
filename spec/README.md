# ReflexAgent Test Suite

This directory contains the test suite for ReflexAgent, organized according to the testing pyramid.

## Testing Pyramid Structure

The test suite is organized into three main layers:

### 1. Unit Tests (`spec/unit/`)

Fast, isolated tests that verify individual components in isolation:

- `spec/unit/core/domain/` - Tests for domain models
- `spec/unit/core/use_cases/` - Tests for business logic use cases
- `spec/unit/core/ports/` - Tests for port interfaces
- `spec/unit/adapters/` - Pure unit tests for simple adapters
- `spec/unit/controllers/` - Isolated controller tests
- `spec/unit/services/` - Tests for simple service objects
- `spec/unit/mailers/` - Tests for mailer templates

**Characteristics:**
- Fast execution (milliseconds)
- No external dependencies (database, Redis, etc.)
- Use mocks and stubs for dependencies
- Focus on a single component

### 2. Integration Tests (`spec/integration/`)

Tests that verify how components work together:

- `spec/integration/adapters/` - Tests for adapter implementations
- `spec/integration/repositories/` - Tests for data persistence
- `spec/integration/controllers/` - Tests for controllers with dependencies
- `spec/integration/services/` - Tests for complex services
- `spec/integration/jobs/` - Tests for background job processing

**Characteristics:**
- Medium speed (sub-second)
- May use test databases or services
- Test multiple components working together
- Verify contracts between components

### 3. End-to-End Tests (`spec/e2e/`)

Tests that verify entire business flows:

- `spec/e2e/flows/` - Full business workflow tests
- `spec/e2e/api/` - API endpoint tests
- `spec/e2e/ui/` - Browser-based UI tests

**Characteristics:**
- Slower execution (seconds)
- Use complete application stack
- Minimal mocking
- Verify business requirements end-to-end

## Running Tests

### Running All Tests

```bash
bundle exec rspec
```

### Running Specific Layers

```bash
# Run only unit tests
PYRAMID_LEVEL=unit bundle exec rspec

# Run only integration tests
PYRAMID_LEVEL=integration bundle exec rspec

# Run only E2E tests
PYRAMID_LEVEL=e2e bundle exec rspec
```

### Including Slow Tests

By default, tests tagged as `:slow` are excluded. To include them:

```bash
RUN_SLOW_TESTS=true bundle exec rspec
```

### Focusing on Specific Tests

Add `:focus` tag to specific test examples or groups:

```ruby
it "does something", :focus do
  # Test code
end
```

Then run with:

```bash
bundle exec rspec
```

## Test Helpers

- `spec/support/` - Contains test helpers, shared examples, and contexts
- `spec/factories/` - Factory definitions for test data creation

## Best Practices

1. **Write at the Right Level**: Place tests at the appropriate level of the pyramid
2. **Isolation**: Unit tests should be isolated from external dependencies
3. **Speed**: Optimize for fast feedback cycles, especially in unit tests
4. **Coverage**: Aim for high coverage in unit and integration tests
5. **Focus**: E2E tests should focus on critical business flows

## CI Pipeline Integration

The CI pipeline runs tests in the following order:

1. Unit tests - Run on every commit
2. Integration tests - Run on every commit (in parallel)
3. E2E tests - Run nightly or before releases 