# Dashboard Required Database Metrics

This document outlines the exact database metrics required by the ReflexAgent dashboard controllers.

## Database Metric Schema

The application primarily uses the `DomainMetric` model, which stores metrics with the following structure:
- `name`: String - The metric identifier
- `value`: Float - The numeric value of the metric
- `dimensions`: JSONB - Additional attributes and dimensions of the metric
- `recorded_at`: DateTime - When the metric was recorded

## Required Database Metrics by Controller

### DashboardsController (`app/controllers/dashboards_controller.rb`)

#### 1. GitHub Push Metrics
| Metric Name | Required Dimensions | Usage |
|-------------|---------------------|-------|
| `github.push.total` | `repository` | Repository activity, time series |
| `github.push.unique_authors` | `author` | Unique contributor tracking |
| `github.push.commits.daily` | `day` | Daily commit volume |

#### 2. DORA Metrics
| Metric Name | Required Dimensions | Usage |
|-------------|---------------------|-------|
| `dora.deployment_frequency` | `period_days`, `rating`, `days_with_deployments`, `total_deployments` | Deployment frequency visualization |
| `dora.lead_time` | `period_days`, `rating`, `sample_size` | Lead time for changes visualization |
| `dora.time_to_restore` | `period_days`, `rating`, `sample_size` | Time to restore service visualization |
| `dora.change_failure_rate` | `period_days`, `rating`, `failures`, `deployments` | Change failure rate visualization |

#### 3. CI/CD Metrics
| Metric Name | Required Dimensions | Usage |
|-------------|---------------------|-------|
| `github.ci.build.total` | `day` | Daily build counts |
| `github.ci.build.duration` | - | Build duration tracking |
| `github.ci.deploy.total` | `day` | Daily deployment counts |
| `github.ci.deploy.duration` | - | Deployment duration tracking |
| `github.workflow_run.completed` | `conclusion` | Alternative deployment tracking |

#### 4. Pull Request Metrics
| Metric Name | Required Dimensions | Usage |
|-------------|---------------------|-------|
| `github.pull_request.opened` | `day` | PR opened tracking |
| `github.pull_request.closed` | `day` | PR closed tracking |
| `github.pull_request.merged` | `day` | PR merged tracking |
| `github.pull_request.review_time` | - | Average PR review time |

### CommitMetricsController (`app/controllers/dashboards/commit_metrics_controller.rb`)

#### 1. Repository Activity Metrics
| Metric Name | Required Dimensions | Usage |
|-------------|---------------------|-------|
| `github.push.total` | `repository` | Top active repositories |

#### 2. Commit Analysis Metrics
| Metric Name | Required Dimensions | Usage |
|-------------|---------------------|-------|
| `github.push.directory_changes.daily` | `directory` | Directory hotspots |
| `github.push.filetype_changes.daily` | `filetype` | File extension hotspots |
| `github.push.commit_type` | `type` | Commit type categorization |
| `github.push.by_author` | `author` | Author activity |
| `github.push.commits` | `day` | Daily commit metrics |

## Database Queries

The controllers rely on the following types of database queries:

### 1. Time Series Data (MetricsService#time_series)
```ruby
DomainMetric.where(name: metric_name)
           .where("recorded_at >= ?", since_date)
           .order(recorded_at: :asc)
```

### 2. Aggregation Queries (MetricsService#aggregate)
```ruby
DomainMetric.where(name: metric_name)
           .where("recorded_at >= ?", since_date)
           .average(:value) # or .sum(:value)
```

### 3. Top Metrics Queries (MetricsService#top_metrics)
```ruby
DomainMetric.where(name: metric_name)
           .where("recorded_at >= ?", since_date)
           .where("dimensions->>'#{dimension}' IS NOT NULL")
           .group("dimensions->>'#{dimension}'")
           .order("count_all DESC")
           .limit(limit)
           .count
```

### 4. DORA Metric Queries
```ruby
DomainMetric.where(name: "dora.deployment_frequency")
           .where("dimensions->>'period_days' = ?", days.to_s)
           .order(recorded_at: :desc)
           .limit(1)
```

## Required Database Fields

For the dashboard to function correctly, the following database fields must be populated:

1. For all metrics:
   - `name` - The metric identifier
   - `value` - The numeric value
   - `recorded_at` - Timestamp for time-based queries
   
2. For metrics with dimensions:
   - `dimensions` - JSONB field with required dimension keys (repository, author, day, etc.)

## Missing or Incomplete Metrics

The controllers include fallback logic for metrics that might be missing:

1. **Code Churn Metrics**: Not fully implemented, defaults to zero values
2. **Breaking Changes**: Not fully implemented, defaults to zero values
3. **CI/CD Metrics**: Attempts multiple metric name patterns if one isn't found 