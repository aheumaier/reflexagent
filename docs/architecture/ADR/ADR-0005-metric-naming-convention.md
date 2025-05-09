# ADR-0005: Metric Naming Convention Standardization

## Status
Accepted

## Context
As ReflexAgent evolves to support multiple data sources beyond GitHub, we need a consistent naming convention for metrics to ensure scalability, maintainability, and coherence. Currently, our metrics naming is inconsistent and tightly coupled to GitHub's event structure. We observed the following issues:

1. Inconsistent naming patterns across different areas of the codebase
2. Lack of clear hierarchical structure in metric names
3. Too much information encoded in names rather than using dimensions
4. No documented standards for adding new metrics
5. Difficult to integrate new data sources with the existing ad-hoc naming approach

## Decision
We will implement a standardized metric naming convention with the following structure:

```
[source].[entity].[action].[detail]
```

Where:
- **source**: The system generating the event (github, bitbucket, jira, etc.)
- **entity**: The primary object being measured (push, pull_request, issue, etc.)
- **action**: The specific operation on the entity (total, created, merged, etc.)
- **detail**: Optional additional context (daily, by_author, duration, etc.)

Additionally:
- We will create a `Domain::Constants::MetricNames` module with standardized constants
- All metric generation will use these constants via helper methods
- Metrics names will be validated against this convention
- We will use dimensions for contextual information rather than encoding it in names
- For cross-source metrics like DORA, we will use dedicated prefixes

## Consequences

### Positive
- Consistent naming across all metrics regardless of source
- Easier to understand metric hierarchies and relationships
- Simpler integration of new data sources
- Better dashboard organization by standardized categories
- Dimensions provide more flexible filtering without naming changes
- Self-documenting code through the constants module

### Negative
- Migration effort for existing metrics that don't follow the convention
- Need to update existing dashboards and visualizations during transition
- Temporary duplication when producing both old and new metric names
- May require stakeholders to learn new metric names

## Alternatives Considered

### 1. Keep Existing Ad-Hoc Approach
We considered maintaining the current approach of creating metrics with ad-hoc names based on event structures. This would avoid migration costs but would become increasingly problematic as we add more data sources.

### 2. Full Event Path Encoding
Another alternative was to fully encode event paths in metric names (e.g., `github.repository.pull_request.review.submitted`). This provides maximum specificity but creates overly long metric names and doesn't separate structure from context well.

### 3. Source-Based Prefixes Only
We considered only standardizing source prefixes (e.g., `github.*`, `jira.*`) and allowing free-form naming after that. This would be simpler to implement but wouldn't solve the underlying structural inconsistencies.

## Implementation Plan

1. Document the convention in `docs/architecture/metrics_naming_convention.md`
2. Create the `Domain::Constants::MetricNames` module with standardized constants
3. Implement helper methods for metric name generation and validation
4. Update the `GithubEventClassifier` to implement the new convention
5. Gradually migrate existing metrics to the new convention
6. Create compatibility layers for dashboard continuity during transition
7. Remove deprecated metric names after transition period

## References
- [Metrics Naming Convention](../metrics_naming_convention.md)
- [Metric Constants Module](../metric_constants.rb)
- [Current GitHub Event Classifier](app/core/domain/classifiers/github_event_classifier.rb) 