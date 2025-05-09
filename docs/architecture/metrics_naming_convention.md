# Metrics Naming Convention

## Overview

This document defines the standardized naming conventions for metrics in ReflexAgent. Following these conventions ensures consistency, clarity, and maintainability as we scale to support multiple event sources beyond GitHub.

## Core Principles

1. **Source-prefixed hierarchy**: All metrics start with their source system
2. **Logical grouping**: Related metrics are grouped under common prefixes
3. **Consistent terminology**: Standard terms used across different sources
4. **Dimension-driven design**: Metrics focus on values, dimensions handle context
5. **Extensibility**: Pattern allows easy addition of new sources

## Naming Pattern

```
[source].[entity].[action].[detail]
```

Where:
- **source**: The system generating the event (github, bitbucket, jira, etc.)
- **entity**: The primary object being measured (push, pull_request, issue, etc.)
- **action**: The specific operation on the entity (total, created, merged, etc.)
- **detail**: Optional additional context (daily, by_author, duration, etc.)

## Standard Sources

| Source     | Description           | Example                             |
|------------|-----------------------|-------------------------------------|
| `github`   | GitHub events         | `github.push.total`                 |
| `bitbucket`| Bitbucket events      | `bitbucket.commit.total`            |
| `jira`     | Jira events           | `jira.issue.created`                |
| `gitlab`   | GitLab events         | `gitlab.merge_request.closed`       |
| `azure`    | Azure DevOps events   | `azure.pipeline.completed`          |
| `jenkins`  | Jenkins events        | `jenkins.build.duration`            |
| `teamcity` | TeamCity events       | `teamcity.deployment.success`       |

## Standardized Entity Names

| Domain        | Entity Names                                                    |
|---------------|----------------------------------------------------------------|
| Git           | `push`, `commit`, `branch`, `tag`                              |
| Code Review   | `pull_request`, `merge_request`, `review`, `comment`           |
| Issues        | `issue`, `bug`, `story`, `task`, `epic`                        |
| CI/CD         | `build`, `test`, `deploy`, `release`, `pipeline`, `workflow`   |
| Repos         | `repository`, `project`                                        |

## Standardized Action Names

| Category      | Action Names                                                    |
|---------------|----------------------------------------------------------------|
| Counting      | `total`, `count`                                               |
| State Changes | `created`, `updated`, `deleted`, `opened`, `closed`, `merged`  |
| Results       | `success`, `failure`, `error`, `completed`, `incident`         |
| Timing        | `duration`, `lead_time`, `time_to_merge`, `time_to_close`      |
| Stats         | `additions`, `deletions`, `churn`, `size`, `complexity`        |

## Standardized Detail Names

| Category      | Detail Names                                                   |
|---------------|----------------------------------------------------------------|
| Time-based    | `daily`, `weekly`, `monthly`, `quarterly`                      |
| Attribution   | `by_author`, `by_team`, `by_directory`, `by_repository`        |
| Code-specific | `directory_changes`, `filetype_changes`, `hotspot`             |
| Quality       | `coverage`, `code_quality`, `technical_debt`                   |

## Metric Categories

### 1. Version Control Metrics

```
[source].push.total
[source].push.commits
[source].push.by_author
[source].commit_volume.daily
[source].push.files_added
[source].push.files_modified
[source].push.files_removed
[source].push.directory_changes
[source].push.directory_hotspot  
[source].push.filetype_changes
[source].push.filetype_hotspot
[source].push.code_additions
[source].push.code_deletions
[source].push.code_churn
```

### 2. Code Review Metrics

```
[source].pull_request.total
[source].pull_request.opened
[source].pull_request.closed
[source].pull_request.merged
[source].pull_request.by_author
[source].pull_request.review_count
[source].pull_request.time_to_merge
[source].pull_request.time_to_first_review
```

### 3. Issue Tracking Metrics

```
[source].issue.total  
[source].issue.opened
[source].issue.closed
[source].issue.by_author
[source].issue.time_to_close
[source].issue.time_to_first_response
```

### 4. CI/CD Metrics

```
[source].ci.build.total
[source].ci.build.success
[source].ci.build.failure
[source].ci.build.duration
[source].ci.test.success
[source].ci.test.duration
[source].ci.deploy.total
[source].ci.deploy.completed
[source].ci.deploy.failed
[source].ci.deploy.duration
[source].ci.deploy.incident
[source].ci.lead_time
```

### 5. Repository Metrics

```
[source].repository.total
[source].repository.created
[source].repository.deleted
[source].repository.registration_event
```

## Cross-Source Metrics

For metrics that combine data from multiple sources (e.g., DORA metrics), use the `dora` prefix:

```
dora.deployment_frequency
dora.lead_time
dora.time_to_restore
dora.change_failure_rate
```

## Dimensions

Instead of encoding all information in metric names, use dimensions to provide context:

| Dimension Category | Example Dimensions                                          |
|--------------------|-------------------------------------------------------------|
| Source             | `repository`, `organization`, `project`, `team`             |
| Time               | `date`, `week`, `month`, `quarter`                          |
| Location           | `directory`, `file`, `branch`, `environment`                |
| Actor              | `author`, `reviewer`, `assignee`                            |
| Type               | `type`, `scope`, `priority`, `severity`                     |
| Result             | `status`, `conclusion`, `action`                            |

## Examples

### GitHub Events

```ruby
create_metric(
  name: "github.pull_request.merged",
  value: 1,
  dimensions: {
    repository: "org/repo",
    author: "username",
    branch: "main"
  }
)
```

### Future Bitbucket Events

```ruby
create_metric(
  name: "bitbucket.pull_request.merged",
  value: 1,
  dimensions: {
    repository: "org/repo",
    author: "username",
    branch: "main"
  }
)
```

## Migration Strategy

For metrics from the GitHub Event Classifier that don't follow this pattern:

1. **Add deprecation comments**: Mark non-compliant metrics as deprecated
2. **Create duplicate metrics**: Generate both old and new names during transition
3. **Update dashboards**: Migrate visualization to use new naming scheme
4. **Remove old metrics**: After transition period, remove deprecated metric names

## Implementation Guidelines

1. Use constants for source names and metric patterns
2. Create helper methods for constructing metric names
3. Validate metric names against the convention
4. Document each metric in the codebase

## Appendix: Current GitHub Metrics Map

| Current Name | Recommended Name |
|--------------|------------------|
| `github.push.total` | Already compliant |
| `github.push.branch_activity` | `github.branch.activity` |
| `github.push.by_author` | Already compliant |
| `github.commit_volume.daily` | Already compliant |
| `github.push.directory_hotspot` | Already compliant |
| `github.ci.build.duration` | Already compliant |
| `github.ci.deploy.completed` | Already compliant |
| `github.ci.lead_time` | Already compliant | 