# Metric Dimension Standards

## Overview

This document defines standardized dimensions for use with metrics in ReflexAgent. While metric names follow a structured format, dimensions provide context and allow for more flexible querying and visualization. Consistent dimension naming is critical for cross-cutting analysis across different data sources.

## Core Principles

1. **Consistency**: Use the same dimension names across different metrics and sources
2. **Specificity**: Dimensions should be specific and unambiguous
3. **Normalization**: Dimension values should be normalized when possible
4. **Extensibility**: Design allows for adding new dimensions without breaking existing queries
5. **Context reduction**: Dimensions extract contextual information from metrics, simplifying metric names

## Standard Dimension Categories

### 1. Source Dimensions

These dimensions identify the source of the data:

| Dimension      | Description                                | Example Values             |
|----------------|--------------------------------------------|----------------------------|
| `source`       | The system that generated the event        | `github`, `jira`, `bitbucket` |
| `repository`   | The repository identifier                  | `org/repo-name`           |
| `organization` | The organization or account                | `acme-corp`               |
| `project`      | The project identifier                     | `acme-website`            |
| `team`         | The team associated with the event         | `platform-team`           |

### 2. Time Dimensions

These dimensions provide temporal context:

| Dimension      | Description                                | Example Values             |
|----------------|--------------------------------------------|----------------------------|
| `date`         | The date of the event                      | `2023-06-15`              |
| `timestamp`    | The precise timestamp of the event         | `2023-06-15T14:22:37Z`    |
| `week`         | The ISO week number                        | `2023-W24`                |
| `month`        | The month of the event                     | `2023-06`                 |
| `quarter`      | The quarter of the event                   | `2023-Q2`                 |
| `commit_date`  | The date of the commit (may differ from event date) | `2023-06-14`     |
| `delivery_date`| The date the event was processed           | `2023-06-15`              |

### 3. Actor Dimensions

These dimensions identify actors in the system:

| Dimension      | Description                                | Example Values             |
|----------------|--------------------------------------------|----------------------------|
| `author`       | The person who created the content         | `username`                |
| `reviewer`     | The person who reviewed the content        | `reviewer-username`       |
| `assignee`     | The person assigned to the item            | `assignee-username`       |
| `committer`    | The person who committed the code (may differ from author) | `committer-username` |
| `requestor`    | The person who requested a change          | `requestor-username`      |

### 4. Content Dimensions

These dimensions describe the content or location:

| Dimension      | Description                                | Example Values             |
|----------------|--------------------------------------------|----------------------------|
| `branch`       | The branch name                            | `main`, `feature/123`      |
| `directory`    | The directory path                         | `src/components`           |
| `filetype`     | The file extension or type                 | `js`, `rb`, `test`         |
| `environment`  | The deployment environment                 | `production`, `staging`    |
| `component`    | The component or service                   | `auth-service`             |
| `labels`       | Labels or tags (comma-separated)           | `bug,frontend,urgent`      |

### 5. Classification Dimensions

These dimensions classify or categorize the event:

| Dimension      | Description                                | Example Values             |
|----------------|--------------------------------------------|----------------------------|
| `type`         | The type or category                       | `feat`, `fix`, `docs`      |
| `scope`        | The scope or area affected                 | `auth`, `ui`, `api`        |
| `priority`     | The priority level                         | `high`, `medium`, `low`    |
| `severity`     | The severity level                         | `critical`, `major`, `minor` |
| `status`       | The current status                         | `open`, `closed`, `merged` |
| `action`       | The action performed                       | `opened`, `closed`, `merged` |
| `conclusion`   | The outcome or result                      | `success`, `failure`       |
| `conventional` | Whether follows conventional format         | `true`, `false`           |

### 6. Measurement Dimensions

These dimensions provide measurement context:

| Dimension      | Description                                | Example Values             |
|----------------|--------------------------------------------|----------------------------|
| `unit`         | The unit of measurement                    | `seconds`, `count`, `percentage` |
| `aggregation`  | The aggregation method used                | `sum`, `avg`, `max`        |
| `interval`     | The measurement interval                   | `daily`, `hourly`          |
| `baseline`     | The baseline or comparison point           | `previous_week`, `target`  |

## Dimension Value Standardization

### Time Format Standards

- **Dates**: Use ISO 8601 format (`YYYY-MM-DD`)
- **Timestamps**: Use ISO 8601 with timezone (`YYYY-MM-DDThh:mm:ssZ`)
- **Weeks**: Use ISO week format (`YYYY-Www`)
- **Months**: Use year-month format (`YYYY-MM`)
- **Quarters**: Use year-quarter format (`YYYY-Qn`)

### Repository Format Standards

- Use `organization/repository` format
- For monorepos, consider using `organization/repository//subproject`

### Branch Format Standards

- Use exact branch name from source
- For tags, use `tag:tag-name` prefix to distinguish
- For PRs, use `pr:123` format

### Boolean Value Standards

- Use string literals `"true"` and `"false"` for boolean dimensions
- Never use `"yes"`, `"no"`, `"1"`, `"0"`, etc.

## Implementation Guidelines

1. Extract dimensions consistently across all adapters
2. Normalize dimension values (e.g., lowercase repository names)
3. Create helper methods for common dimension extraction
4. Validate dimension values against expected formats
5. Document new dimensions when they are added

## Example Usage

```ruby
create_metric(
  name: "github.pull_request.merged",
  value: 1,
  dimensions: {
    # Source dimensions
    repository: "acme-corp/website",
    organization: "acme-corp",
    source: "github",
    
    # Time dimensions
    date: Time.now.strftime("%Y-%m-%d"),
    
    # Actor dimensions
    author: "janesmith",
    reviewer: "johndoe",
    
    # Content dimensions
    branch: "feature/login-redesign",
    
    # Classification dimensions
    type: "feat",
    scope: "ui",
    
    # Measurement dimensions
    unit: "count"
  }
)
```

## Dimension Migration Strategy

For existing metrics with non-standard dimensions:

1. Identify current dimension usage patterns
2. Create mapping between old and new dimension names
3. Update extractors to normalize dimension names
4. Add compatibility layer for queries during transition
5. Update dashboards to use standardized dimensions

## Related Documents

- [Metrics Naming Convention](metrics_naming_convention.md)
- [ADR-0005: Metric Naming Standardization](ADR/ADR-0005-metric-naming-convention.md)
- [Metric Constants](metric_constants.rb) 