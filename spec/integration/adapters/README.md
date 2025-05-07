# Adapter Tests for ReflexAgent

This directory contains tests for the adapter implementations in the ReflexAgent application.

## Testing Approach

The adapter tests follow these principles:

1. **Interface Compliance**: Tests verify that adapters properly implement their port interfaces.
2. **Real Implementations**: Tests use real adapter implementations (not mocks).
3. **Isolation**: External dependencies (Redis, Sidekiq, Email) are mocked or configured in test mode.
4. **Edge Cases**: Tests include handling for empty/nil inputs and error conditions.

## Test Structure

### Repository Adapters

- `event_repository_spec.rb`: Tests for the EventRepository adapter
- `metric_repository_spec.rb`: Tests for the MetricRepository adapter
- `alert_repository_spec.rb`: Tests for the AlertRepository adapter

In a full implementation with ActiveRecord, these tests would verify that:
- Records are properly created in the database
- Finder methods return the correct records
- Domain objects are properly mapped to and from database records

### Cache Adapter

- `redis_cache_spec.rb`: Tests for the RedisCache adapter

These tests verify that:
- Metrics are properly cached
- Cached metrics can be retrieved
- Cache can be cleared (entirely or selectively)

### Notification Adapters

- `slack_notifier_spec.rb`: Tests for the SlackNotifier adapter
- `email_notifier_spec.rb`: Tests for the EmailNotifier adapter

These tests verify that:
- Alerts are properly formatted and sent
- Messages to specific channels are delivered

### Queue Adapter

- `process_event_worker_spec.rb`: Tests for the ProcessEventWorker adapter

These tests verify that:
- Jobs are properly enqueued in Sidekiq
- Job parameters are correctly set

## Running the Tests

You can run all adapter tests with:

```bash
bundle exec rspec spec/adapters
```

Or run tests for a specific adapter:

```bash
bundle exec rspec spec/adapters/repositories
bundle exec rspec spec/adapters/cache
bundle exec rspec spec/adapters/notifications
bundle exec rspec spec/adapters/queue
``` 