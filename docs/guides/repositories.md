# Developer Guide: Working with Repositories

This guide provides practical guidance on how to work with and extend the repository layer in ReflexAgent.

## Table of Contents

1. [Introduction](#introduction)
2. [Repository Types](#repository-types)
3. [Using Repositories](#using-repositories)
4. [Error Handling](#error-handling)
5. [Creating New Repository Methods](#creating-new-repository-methods)
6. [Testing Repositories](#testing-repositories)
7. [Common Patterns](#common-patterns)

## Introduction

Repositories in ReflexAgent are adapters that implement the `StoragePort` interface, providing persistence capabilities for domain models. They form a bridge between the core domain logic and the database, abstracting database-specific details from domain code.

## Repository Types

ReflexAgent includes several repository types for different domains:

1. **BaseMetricRepository**: Common functionality for all metric repositories.
2. **GitMetricRepository**: Specialized for Git-related metrics.
3. **DoraMetricsRepository**: Specialized for DORA metrics.
4. **IssueMetricRepository**: Specialized for Issue metrics.
5. **EventRepository**: For event storage and retrieval.
6. **TeamRepository**: For team configuration data.
7. **AlertRepository**: For alert storage and retrieval.

## Using Repositories

### Obtaining a Repository Instance

Repositories are typically created through the `MetricRepositoryFactory`:

```ruby
# In a use case
def initialize(storage_port: nil, logger_port: nil)
  @storage_port = storage_port || DependencyContainer.resolve(:storage_port)
  @logger_port = logger_port || DependencyContainer.resolve(:logger_port)
  
  # Get a specific repository type if needed
  @git_repo = MetricRepositoryFactory.create_repository(
    :git, 
    logger_port: @logger_port
  )
end
```

### Basic CRUD Operations

All metric repositories provide standard CRUD operations:

```ruby
# Create
metric = Domain::Metric.new(
  name: "git.commit.count",
  value: 42,
  source: "github",
  dimensions: { "repo" => "acme/project" },
  timestamp: Time.now
)
saved_metric = repository.save_metric(metric)

# Read
found_metric = repository.find_metric(saved_metric.id)

# Update
updated_metric = found_metric.with_value(43)
repository.update_metric(updated_metric)

# List (Read multiple)
metrics = repository.list_metrics(
  name: "git.commit.count",
  source: "github",
  start_time: 1.week.ago,
  end_time: Time.now
)
```

### Query Methods

Beyond CRUD, repositories offer specialized query methods:

```ruby
# Pattern-based queries
commits = repository.find_by_pattern(
  source: "github",
  entity: "commit",
  action: "count",
  start_time: 1.month.ago,
  end_time: Time.now,
  dimensions: { "repo" => "acme/project" }
)

# Source-based queries
github_metrics = repository.find_by_source(
  "github", 
  start_time: 1.month.ago,
  end_time: Time.now
)

# Entity-based queries
commit_metrics = repository.find_by_entity(
  "commit", 
  start_time: 1.month.ago,
  end_time: Time.now
)

# Statistical queries
average = repository.get_average(
  "git.commit.time_to_merge", 
  1.month.ago, 
  Time.now
)

p95 = repository.get_percentile(
  "git.commit.time_to_merge", 
  95, 
  1.month.ago, 
  Time.now
)
```

### Specialized Repository Methods

Each specialized repository provides domain-specific methods:

```ruby
# GitMetricRepository
git_repo.get_time_to_merge_for_repository("acme/project")
git_repo.get_pull_request_metrics(repository: "acme/project")
git_repo.get_commit_volume_by_author("acme/project")

# DoraMetricsRepository
dora_repo.get_deployment_frequency(team: "platform-team")
dora_repo.get_lead_time_for_changes(team: "platform-team")
dora_repo.get_change_failure_rate(team: "platform-team")
dora_repo.get_mean_time_to_recovery(service: "payment-api")

# IssueMetricRepository
issue_repo.get_time_to_resolution(project: "payment-system")
issue_repo.get_issue_creation_rate(project: "payment-system")
issue_repo.get_backlog_metrics(team: "platform-team")
```

## Error Handling

All repositories use a consistent error handling approach through the `ErrorHandler` concern. 

### Error Types

When working with repositories, you may encounter these error types:

- `MetricRepositoryError`: Base class for all repository errors
  - `DatabaseError`: Database operation failures
  - `ValidationError`: Input validation failures
  - `QueryError`: Query construction/execution errors
  - `NotFoundError`: "Not found" scenarios
  - `UnsupportedOperationError`: Unsupported operations

### Handling Repository Errors

```ruby
begin
  repository.find_metric(id)
rescue Repositories::Errors::NotFoundError => e
  # Handle not found case
  log_warning("Metric not found: #{e.id}")
  nil
rescue Repositories::Errors::DatabaseError => e
  # Handle database error
  log_error("Database error: #{e.message}, Operation: #{e.operation}")
  raise ServiceUnavailableError, "Repository unavailable"
rescue Repositories::Errors::MetricRepositoryError => e
  # Handle any repository error
  log_error("Repository error: #{e.message}")
  raise
end
```

## Creating New Repository Methods

When adding methods to repositories, follow these guidelines:

### Method Implementation Pattern

```ruby
def get_some_metric(param1, param2)
  # Set up context for error handling
  context = {
    param1: param1,
    param2: param2,
    operation: "get_some_metric"
  }
  
  # Validate inputs
  raise ArgumentError, "param1 cannot be nil" if param1.nil?
  
  # Use error handler methods for database operations
  handle_database_error("get_some_metric", context) do
    # Database operation here
    result = SomeModel.where(param1: param1, param2: param2)
    
    # Process result
    process_result(result)
  end
end

private def process_result(result)
  # Transform database results to domain objects
  result.map do |item|
    to_domain_metric(item)
  end
end
```

### Guidelines for New Methods

1. **Use Error Handler Methods**: Always wrap database operations with `handle_database_error`, `handle_query_error`, etc.
2. **Validate Inputs**: Validate inputs early to prevent invalid data from reaching the database.
3. **Provide Context**: Include relevant context in error handling.
4. **Return Domain Objects**: Methods should return domain objects, not database models.
5. **Keep Methods Focused**: Each method should do one thing well.

## Testing Repositories

### Unit Testing

```ruby
RSpec.describe Repositories::GitMetricRepository do
  let(:logger_port) { instance_double("LoggerPort", error: nil, warn: nil, info: nil) }
  let(:repository) { described_class.new(logger_port: logger_port) }
  
  describe "#get_time_to_merge_for_repository" do
    it "returns the average time to merge for a repository" do
      # Setup test data
      repo_name = "acme/project"
      create_test_metrics(repo_name)
      
      # Call the method
      result = repository.get_time_to_merge_for_repository(repo_name)
      
      # Assertions
      expect(result).to be_a(Float)
      expect(result).to be > 0
    end
    
    it "returns nil when no data is available" do
      result = repository.get_time_to_merge_for_repository("nonexistent/repo")
      expect(result).to be_nil
    end
    
    it "handles errors correctly" do
      allow(DomainMetric).to receive(:where).and_raise(ActiveRecord::StatementInvalid, "DB error")
      
      expect {
        repository.get_time_to_merge_for_repository("acme/project")
      }.to raise_error(Repositories::Errors::DatabaseError)
    end
  end
  
  private
  
  def create_test_metrics(repo_name)
    # Create test metrics in the database
  end
end
```

### Integration Testing

```ruby
RSpec.describe "Repository Integration", type: :integration do
  let(:git_repo) { MetricRepositoryFactory.create_repository(:git) }
  
  before(:all) do
    # Set up test database
    DatabaseCleaner.clean
    # Create test data
    create_test_data
  end
  
  it "correctly retrieves and processes metrics" do
    # Test repository with actual database
    result = git_repo.get_time_to_merge_for_repository("acme/project")
    expect(result).to be_within(0.1).of(expected_value)
  end
  
  private
  
  def create_test_data
    # Create test data in the database
  end
end
```

## Common Patterns

### Caching Strategy

Repositories often implement caching for frequently accessed data:

```ruby
def get_frequently_accessed_data(key)
  # Check cache first
  if @cache.key?(key)
    return @cache[key]
  end
  
  # If not in cache, fetch from database
  data = fetch_from_database(key)
  
  # Cache the result if it's not nil
  @cache[key] = data if data
  
  data
end
```

### Dimension Filtering

When filtering by dimensions, use consistent patterns:

```ruby
# Single dimension matching
def find_by_dimension(dimension_name, dimension_value)
  # Rails 5+ supports jsonb containment with hash syntax
  where("dimensions @> ?", { dimension_name => dimension_value }.to_json)
end

# Multiple dimensions matching
def find_by_dimensions(dimensions_hash)
  where("dimensions @> ?", dimensions_hash.to_json)
end
```

### Time Range Filtering

Always use time range filtering to improve performance:

```ruby
def with_time_range(query, start_time, end_time)
  if start_time && end_time
    query = query.where(recorded_at: start_time..end_time)
  elsif start_time
    query = query.where("recorded_at >= ?", start_time)
  elsif end_time
    query = query.where("recorded_at <= ?", end_time)
  end
  
  query
end
``` 