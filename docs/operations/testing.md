# Testing Pyramid in ReflexAgent

This document explains how testing is organized according to the Testing Pyramid pattern in ReflexAgent.

## Testing Pyramid Overview

The testing pyramid is a concept that emphasizes having:

- Many unit tests (fast, focused)
- Fewer integration tests (medium speed, crossing boundaries)
- Even fewer end-to-end tests (slow, full system)

```
      /\
     /  \
    /E2E \
   /      \
  /        \
 /Integration\
/              \
/     Unit      \
------------------
```

## Our Implementation

The testing pyramid is implemented in our project through:

1. Directory structure:
   - `spec/unit/` - Unit tests
   - `spec/integration/` - Integration tests
   - `spec/e2e/` - End-to-end tests

2. Configuration in `spec/support/testing_pyramid.rb`:
   - Automatically tags tests based on their location
   - Configures filters for running specific pyramid levels
   - Sets up metadata like `:slow` for E2E tests

3. Rake tasks in `lib/tasks/test.rake`:
   - `rake test:unit` - Run unit tests
   - `rake test:integration` - Run integration tests 
   - `rake test:e2e` - Run end-to-end tests
   - `rake test:pyramid` - Run all tests in pyramid order

4. CI Pipeline in `.github/workflows/ci.yml`:
   - Runs each level separately using Rake tasks
   - Runs tests in pyramid order (unit, integration, e2e)

## Running Tests

### Using Rake Tasks (Recommended)

To run tests at a specific pyramid level:

```bash
# Run only unit tests
bundle exec rake test:unit

# Run only integration tests
bundle exec rake test:integration

# Run only E2E tests
bundle exec rake test:e2e

# Run all tests in pyramid order
bundle exec rake test:pyramid
```

### Using RSpec Directly

You can also run tests using RSpec directly:

```bash
# Run only unit tests
PYRAMID_LEVEL=unit bundle exec rspec

# Run only integration tests
PYRAMID_LEVEL=integration bundle exec rspec

# Run only E2E tests
PYRAMID_LEVEL=e2e RUN_SLOW_TESTS=true bundle exec rspec

# Run all tests
bundle exec rspec
```

## Guidelines for Writing Tests

1. **Unit Tests (`spec/unit/`)**:
   - Test individual components in isolation
   - Use mocks/stubs for external dependencies
   - Focus on business logic, domain models, and use cases
   - Should be very fast to run

2. **Integration Tests (`spec/integration/`)**:
   - Test how components work together
   - Focus on adapters, repositories, controllers with dependencies
   - May use test databases or services
   - Run at medium speed

3. **End-to-End Tests (`spec/e2e/`)**:
   - Test entire business flows
   - Minimal mocking
   - Exercise the whole system
   - Slower to run, focus on critical paths

## Continuous Integration

In our CI pipeline:

1. Unit tests run first (fast feedback)
2. Integration tests run next
3. E2E tests run last

If any level fails, the build fails. This gives us quick feedback while ensuring complete test coverage. 