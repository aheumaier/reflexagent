# Metrics Indexing Strategy

## Overview

This document outlines the indexing strategy for the `metrics` table to optimize query performance for various access patterns.

## Table Structure

The `metrics` table is partitioned by `recorded_at` to efficiently manage time-series data. Each partition corresponds to a month of data.

## Index Types

### 1. Single-Column Indexes

- `metrics_name_idx` - On `name` column (existed previously)
- `idx_metrics_name` - On `name` column (additional optimized index)
- `metrics_recorded_at_idx` - On `recorded_at` column (existed previously)
- `idx_metrics_source` - On `source` column (newly added)

### 2. Composite Indexes

- `metrics_name_recorded_at_idx` - On `(name, recorded_at)` (existed previously)
- `idx_metrics_name_source_recorded_at` - On `(name, source, recorded_at)` (newly added)

### 3. JSONB Indexes

- `idx_metrics_dimensions` - GIN index on `dimensions` column (newly added)
- `idx_metrics_dimensions_path_ops` - GIN index with `jsonb_path_ops` on dimensions (newly added)

## Index Details

### `idx_metrics_name_source_recorded_at`

This composite index is particularly valuable for queries that filter on multiple columns. It provides benefits for:

1. **Query Patterns**: Significantly improves performance for queries that filter by:
   - Specific metric name + source + time range
   - Specific metric name + source (with or without time range)
   - Specific metric name (with or without time range)

2. **Prefix Matching**: PostgreSQL can use this index when any prefix of the indexed columns is used in the query:
   - `WHERE name = 'github.push.commits'` (using the first column)
   - `WHERE name = 'github.push.commits' AND source = 'webhook'` (using the first two columns)
   - `WHERE name = 'github.push.commits' AND source = 'webhook' AND recorded_at > '2025-01-01'` (using all three columns)

3. **Common Repository Methods**:
   - `list_metrics(name:, start_time:, end_time:)` - Improves performance when filtering by metric name and time range
   - `find_metrics_by_name_and_dimensions(name, dimensions, start_time)` - Benefits the name + time filtering aspect
   - Analytics methods that filter by metric name, source, and time range

4. **Sort Operations**: This index can also support sorting by these columns in the specific order they appear in the index.

### JSONB Indexes

We use two different GIN indexes for the `dimensions` column:

1. **`idx_metrics_dimensions`**:
   - Standard GIN index on the JSONB column
   - Supports all JSONB operators (`@>`, `?`, `?&`, `?|`, etc.)
   - Larger index size but more versatile

2. **`idx_metrics_dimensions_path_ops`**:
   - Uses the `jsonb_path_ops` operator class
   - More efficient for the containment operator (`@>`)
   - Smaller index size but limited to `@>` operator only
   - Better performance for typical dimension filtering queries

For queries that filter by both name and dimensions, PostgreSQL will use:
1. The `idx_metrics_name` index to filter by name
2. The `idx_metrics_dimensions_path_ops` index to filter by dimensions

## Index Maintenance

All indexes are automatically created for:

1. The main `metrics` table
2. Each monthly partition (current and next month)
3. Any new partitions created via:
   - The `metrics:create_partition` Rake task
   - The `MetricsMaintenanceJob` Sidekiq job

## Performance Impact

These indexes will significantly improve performance for:

1. **Filtering Operations**:
   - Faster filtering by name, source, dimensions, and time ranges
   - Optimized lookups of metrics with specific dimension values
   - Better performance for analytics queries

2. **Trade-offs**:
   - Write operations will be slightly slower due to index maintenance
   - Storage requirements will increase (particularly for the GIN indexes)

## Usage Recommendations

1. When querying the `metrics` table, prioritize filtering by indexed columns (name, source, recorded_at)
2. For queries that filter on dimensions, use the `@>` operator to leverage the GIN index with jsonb_path_ops
3. Consider the order of columns in WHERE clauses to match index order when possible

## Monitoring

To ensure these indexes are being used effectively:

1. Regularly run `EXPLAIN ANALYZE` on common query patterns
2. Watch for sequential scans in the PostgreSQL logs
3. Use the `metrics:analyze` Rake task to update PostgreSQL statistics 