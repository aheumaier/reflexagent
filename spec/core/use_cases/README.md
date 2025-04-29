# Use Case Tests for ReflexAgent

This directory contains the tests for the core use cases that implement the business logic of the ReflexAgent application.

## Testing Approach

The use case tests follow these principles:

1. **Isolation**: Each use case is tested in isolation from external dependencies.
2. **Dependency Injection**: Test doubles are injected via the DependencyContainer to replace real implementations.
3. **Behavior Verification**: Tests verify that the use case correctly interacts with its ports.
4. **Edge Cases**: Tests include error handling and boundary conditions.

## Test Doubles

All tests use the mock implementations defined in `spec/support/hexagonal_helpers.rb`:

- **MockStoragePort**: For storing and retrieving events, metrics, and alerts
- **MockCachePort**: For caching metric data
- **MockNotificationPort**: For sending alerts and messages
- **MockQueuePort**: For enqueuing jobs

## Use Cases

### ProcessEvent

Tests verify that the ProcessEvent use case:
- Saves the incoming event via the storage port
- Enqueues metric calculation via the queue port
- Handles errors appropriately

### CalculateMetrics

Tests verify that the CalculateMetrics use case:
- Retrieves the event from the storage port
- Creates metrics based on event data
- Saves the metrics via the storage port
- Caches the metrics via the cache port
- Handles errors appropriately

### DetectAnomalies

Tests verify that the DetectAnomalies use case:
- Evaluates metrics against thresholds
- Creates alerts for anomalous metrics
- Saves alerts via the storage port
- Notifies about alerts via the notification port
- Handles errors appropriately

### SendNotification

Tests verify that the SendNotification use case:
- Retrieves alerts from the storage port
- Sends alerts via the notification port
- Sends messages to specified channels
- Handles errors appropriately

## Running the Tests

You can run all use case tests with:

```bash
bundle exec rspec spec/core/use_cases
```

Or run tests for a specific use case:

```bash
bundle exec rspec spec/core/use_cases/process_event_spec.rb
bundle exec rspec spec/core/use_cases/calculate_metrics_spec.rb
bundle exec rspec spec/core/use_cases/detect_anomalies_spec.rb
bundle exec rspec spec/core/use_cases/send_notification_spec.rb
``` 