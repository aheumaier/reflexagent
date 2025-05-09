# Metrics Migration Guide

This document provides a step-by-step guide for migrating existing metrics to the new standardized naming convention.

## Overview

As part of our [ADR-0005: Metric Naming Standardization](../architecture/ADR/ADR-0005-metric-naming-convention.md), we need to migrate existing metrics to follow our new naming convention. This migration must be handled carefully to ensure:

1. Continuity of existing dashboards and reports
2. No data loss during the transition
3. Minimal disruption to users and services

## Migration Strategy

We will use a phased approach with backward compatibility:

### Phase 1: Dual Emission (Current)

- Generate both old and new metric names simultaneously
- Update new code to use only new naming convention
- Keep existing dashboards on old metric names

### Phase 2: Dashboard Migration (Month 1-2)

- Update dashboards and visualizations to use new metric names
- Verify all alerts and reports are working correctly
- Communicate changes to stakeholders

### Phase 3: Deprecation (Month 3)

- Mark old metric names as deprecated in code
- Add warnings in logs when old names are used
- Begin updating documentation and references

### Phase 4: Removal (Month 4+)

- Remove generation of deprecated metric names
- Clean up legacy code
- Finalize documentation

## Implementation Guide

### Step 1: Identify Metrics to Migrate

1. Use the following command to identify all metric names in the codebase:

```bash
grep -r "name: \"github." --include="*.rb" app/
```

2. Compare found metrics against the [standardized naming conventions](../architecture/metrics_naming_convention.md)
3. Create a mapping table of old names to new names in the format:

```ruby
LEGACY_METRIC_MAPPING = {
  "github.push.branch_activity" => "github.branch.activity",
  "github.workflow_job.completed" => "github.workflow_job.conclusion.completed",
  # Add other mappings...
}
```

### Step 2: Update the Metric Creation Logic

1. Modify the `create_metric` method in `BaseClassifier` to support dual emission:

```ruby
def create_metric(name:, value:, dimensions: {}, timestamp: nil)
  # Create the metric with original name
  metric = Domain::Metric.new(
    name: name,
    value: value,
    dimensions: dimensions,
    timestamp: timestamp
  )
  
  # Check if this metric has a new standardized name
  if LEGACY_METRIC_MAPPING.key?(name)
    # Also create a metric with the new name
    new_name = LEGACY_METRIC_MAPPING[name]
    new_metric = Domain::Metric.new(
      name: new_name,
      value: value,
      dimensions: dimensions,
      timestamp: timestamp
    )
    
    # Return both metrics as an array
    [metric, new_metric]
  else
    # Return just the original metric
    metric
  end
end
```

2. Update metrics array handling in classifier methods:

```ruby
def classify_example_event(event)
  metrics = []
  
  # When adding metrics, handle the possibility of arrays being returned
  result = create_metric(
    name: "github.example.total",
    value: 1,
    dimensions: dimensions
  )
  
  if result.is_a?(Array)
    metrics.concat(result)
  else
    metrics << result
  end
  
  # Rest of the method...
  
  { metrics: metrics }
end
```

### Step 3: Update Dashboard Queries

For each dashboard:

1. Create a copy of the existing dashboard
2. Update metric name references to use new naming convention
3. Test the new dashboard with sample data
4. Once verified, replace the old dashboard

Example SQL transformation:

```sql
-- Before
SELECT COUNT(*) FROM metrics WHERE name = 'github.push.branch_activity' 

-- After
SELECT COUNT(*) FROM metrics WHERE name = 'github.branch.activity'
```

### Step 4: Add Deprecation Warnings

After dashboards are migrated:

1. Add log warnings when old metric names are used:

```ruby
def create_metric(name:, value:, dimensions: {}, timestamp: nil)
  if LEGACY_METRIC_MAPPING.key?(name)
    Rails.logger.warn(
      "DEPRECATED METRIC NAME: '#{name}' will be removed in future versions. " \
      "Use '#{LEGACY_METRIC_MAPPING[name]}' instead."
    )
  end
  
  # Rest of the method...
end
```

2. Add deprecation notices in documentation

### Step 5: Clean Up

Once the migration is complete:

1. Remove the dual emission code
2. Update tests to use only new metric names
3. Remove legacy mapping tables
4. Update all documentation to reference only new metric names

## Example Migration Mappings

Below is a sample of old metric names mapped to their new standardized equivalents:

| Current Name | New Standardized Name |
|--------------|----------------------|
| `github.push.branch_activity` | `github.branch.activity` |
| `github.commit.directory_change` | `github.commit.directory_changes` |
| `github.commit.file_extension` | `github.commit.filetype_changes` |
| `github.commit.code_volume` | `github.commit.code_churn` |
| `github.workflow_job.completed` | `github.workflow_job.conclusion.completed` |

## Testing Strategy

For each metric being migrated:

1. Create test events that generate the metric
2. Verify both old and new metrics are emitted during Phase 1
3. Verify dimension values match between old and new metrics
4. Test dashboard queries with both old and new names
5. Verify alerts and reports continue to function

## Rollback Plan

If issues are discovered during migration:

1. Revert the `create_metric` method to its original implementation
2. Restore original dashboard queries
3. Re-evaluate the migration strategy
4. Address any data inconsistencies

## Timeline

- **Week 1-2**: Implement dual emission
- **Week 3-6**: Migrate dashboards
- **Week 7-8**: Add deprecation warnings
- **Week 9+**: Begin phasing out old metric names

## Related Documents

- [Metrics Naming Convention](../architecture/metrics_naming_convention.md)
- [ADR-0005: Metric Naming Standardization](../architecture/ADR/ADR-0005-metric-naming-convention.md)
- [Dimension Standards](../architecture/dimension_standards.md) 