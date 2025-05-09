# ReflexAgent Services Layer Documentation

This document provides comprehensive technical documentation for the services layer of ReflexAgent, focusing on the `DoraService` and `MetricsService` classes. These services are core components that implement business logic for metric calculations and data analysis.

## Overview

The services layer follows these principles:
1. Provides a clean API for business logic operations
2. Depends on ports/adapters for data access (hexagonal architecture)
3. Implements caching strategies for performance optimization
4. Handles fallbacks for missing or incomplete data

## DoraService

`DoraService` implements the Four Key Metrics from the DORA (DevOps Research and Assessment) research program. The service calculates standardized DevOps performance metrics that correlate with organizational success.

### Initialization

```ruby
def initialize(storage_port:)
  @storage_port = storage_port
end
```

The service requires a `storage_port` that implements the `StoragePort` interface for retrieving metrics from the database.

### Public Methods

#### `deployment_frequency(days = 30)`

Calculates how often deployments occur (deployments per day).

**Parameters:**
- `days` (Integer): Time period to analyze, defaults to 30 days

**Returns:** 
- Hash containing:
  - `value` (Float): Deployments per day
  - `rating` (String): Performance rating (elite, high, medium, low)
  - `days_with_deployments` (Integer): Number of days with at least one deployment
  - `total_days` (Integer): Total days analyzed
  - `total_deployments` (Integer): Total number of deployments

**Metric Sources (tried in order):**
1. `github.ci.deploy.completed`
2. `github.deployment_status.success`
3. `github.deployment.total`

**Rating Criteria:**
- Elite: ≥ 1 deployment per day
- High: Between once per day and once per week (≥ 0.14)
- Medium: Between once per week and once per month (≥ 0.03)
- Low: Less than once per month

#### `lead_time_for_changes(days = 30)`

Calculates the time from code commit to production deployment.

**Parameters:**
- `days` (Integer): Time period to analyze, defaults to 30 days

**Returns:**
- Hash containing:
  - `value` (Float): Average lead time in hours
  - `rating` (String): Performance rating (elite, high, medium, low)
  - `sample_size` (Integer): Number of deployments analyzed

**Metric Sources:**
- `github.ci.lead_time`

**Rating Criteria:**
- Elite: < 24 hours
- High: < 1 week (168 hours)
- Medium: < 1 month (730 hours)
- Low: > 1 month

#### `time_to_restore_service(days = 30)`

Calculates the average time to restore service after an incident.

**Parameters:**
- `days` (Integer): Time period to analyze, defaults to 30 days

**Returns:**
- Hash containing:
  - `value` (Float): Average restoration time in hours
  - `rating` (String): Performance rating (elite, high, medium, low)
  - `sample_size` (Integer): Number of incidents analyzed

**Metric Sources:**
- `incident.resolution_time`

**Rating Criteria:**
- Elite: < 1 hour
- High: < 1 day (24 hours)
- Medium: < 1 week (168 hours)
- Low: > 1 week

#### `change_failure_rate(days = 30)`

Calculates the percentage of deployments causing incidents or failures.

**Parameters:**
- `days` (Integer): Time period to analyze, defaults to 30 days

**Returns:**
- Hash containing:
  - `value` (Float): Failure rate percentage (0-100)
  - `rating` (String): Performance rating (elite, high, medium, low)
  - `failures` (Integer): Number of failed deployments
  - `deployments` (Integer): Total number of deployments

**Metric Sources:**
- Deployments (tried in order):
  1. `github.ci.deploy.completed`
  2. `github.deployment_status.success`
  3. `github.deployment.total`
- Failures (tried in order):
  1. `github.ci.deploy.incident`
  2. `github.deployment_status.failure`

**Rating Criteria:**
- Elite: 0-15%
- High: 16-30%
- Medium: 31-45%
- Low: 46-100%

## MetricsService

`MetricsService` provides a comprehensive API for retrieving, aggregating, and analyzing various engineering metrics. The service supports time series visualization, dimension-based analysis, and statistical aggregations.

### Initialization

```ruby
def initialize(storage_port:, cache_port:)
  @storage_port = storage_port
  @cache_port = cache_port
end
```

The service requires:
- `storage_port`: Implements the `StoragePort` interface for database access
- `cache_port`: Implements the `CachePort` interface for caching metrics

### Public Methods

#### `aggregate_metrics(metric_name, time_period = "daily", days = 7)`

Groups and aggregates metrics by time period.

**Parameters:**
- `metric_name` (String): The metric to aggregate
- `time_period` (String): Grouping period ("daily", "weekly", "monthly")
- `days` (Integer): Time period to analyze

**Returns:**
- Hash with time periods as keys and aggregated values as values

**Example:**
```ruby
# Returns: {"2023-06-01" => 10, "2023-06-02" => 15, ...}
metrics_service.aggregate_metrics("github.push.total", "daily", 30)
```

#### `top_metrics(metric_name, dimension:, limit: 5, days: 30)`

Ranks metrics by a specific dimension.

**Parameters:**
- `metric_name` (String): The metric to analyze
- `dimension` (Symbol/String): Dimension to group by (e.g., `:repository`, `:author`)
- `limit` (Integer): Maximum number of results
- `days` (Integer): Time period to analyze

**Returns:**
- Hash with dimensions as keys and aggregated values as values, sorted by highest value

**Example:**
```ruby
# Returns: {"repo/frontend" => 45, "repo/backend" => 30, ...}
metrics_service.top_metrics("github.push.total", dimension: "repository", limit: 5, days: 30)
```

#### `success_rate(metric_base_name, days = 30)`

Calculates success percentage for CI/CD operations.

**Parameters:**
- `metric_base_name` (String): Base name of the metric (e.g., "github.ci.build")
- `days` (Integer): Time period to analyze

**Returns:**
- Float: Success rate percentage (0-100)

**Example:**
```ruby
# Returns: 87.5
metrics_service.success_rate("github.ci.build", 14)
```

#### `average_metric(metric_name, days = 30)`

Calculates the average value of a metric.

**Parameters:**
- `metric_name` (String): The metric to analyze
- `days` (Integer): Time period to analyze

**Returns:**
- Float: Average value

#### `team_velocity(weeks = 4)`

Calculates team velocity (completed tasks per week).

**Parameters:**
- `weeks` (Integer): Number of weeks to analyze

**Returns:**
- Float: Average tasks completed per week

**Metric Sources:**
- Any metric matching `task.*.total`

#### `time_series(metric_name, days: 30, interval: "day", unique_by: nil)`

Creates a time series for visualization.

**Parameters:**
- `metric_name` (String): The metric to analyze
- `days` (Integer): Time period to analyze
- `interval` (String): Time grouping ("hour", "day", "week", "month")
- `unique_by` (String/Symbol): Optional dimension for counting unique values

**Returns:**
- Hash with time periods as keys and values as values, chronologically sorted

**Example:**
```ruby
# Returns: {"2023-06-01" => 5, "2023-06-02" => 8, ...}
metrics_service.time_series("github.push.total", days: 30, interval: "day")
```

#### `aggregate(metric_name, days: 30, aggregation: "avg")`

Applies an aggregation function to a metric.

**Parameters:**
- `metric_name` (String): The metric to analyze
- `days` (Integer): Time period to analyze
- `aggregation` (String): Function to apply ("avg", "sum", "max", "min", "count")

**Returns:**
- Float: Result of the aggregation

**Example:**
```ruby
# Returns: 43.2
metrics_service.aggregate("github.ci.build.duration", days: 7, aggregation: "avg")
```

## Implementation Notes

### Error Handling

Both services implement robust error handling:
- Default values are returned when metrics are missing
- Multiple metric sources are tried in succession for DORA metrics
- For visualization, empty intervals are filled with zero values

### Performance Optimization

The services use several techniques to optimize performance:
- Metrics are cached after calculation
- Database queries are minimized by batching requests
- Time series data is pre-processed for chart rendering

### Integration with Dashboard Controllers

Dashboard controllers make extensive use of these services:
- `DashboardsController` uses both services for the main engineering dashboard
- `CommitMetricsController` primarily uses `MetricsService` for commit analysis

## Usage Examples

### Calculate and Store DORA Metrics

```ruby
dora_service = DoraService.new(storage_port: storage_port)
metrics = dora_service.deployment_frequency(30)

# Store calculated metrics
DomainMetric.create(
  name: "dora.deployment_frequency",
  value: metrics[:value],
  dimensions: {
    rating: metrics[:rating],
    period_days: 30,
    days_with_deployments: metrics[:days_with_deployments],
    total_deployments: metrics[:total_deployments]
  }
)
```

### Generate Time Series Data for Charts

```ruby
metrics_service = MetricsService.new(storage_port: storage_port, cache_port: cache_port)

# Get daily commit counts for chart
daily_commits = metrics_service.time_series("github.push.total", days: 90, interval: "day")

# Get unique authors per week
weekly_authors = metrics_service.time_series(
  "github.push.unique_authors", 
  days: 90, 
  interval: "week", 
  unique_by: "author"
)
``` 