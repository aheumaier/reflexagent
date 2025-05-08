# Lead Time for Changes - DORA Metrics

This document explains how to use the Lead Time for Changes DORA metric calculation tools in ReflexAgent.

## What is Lead Time for Changes?

Lead Time for Changes measures the time it takes for a code change to go from commit to successfully running in production. It reflects your team's efficiency in delivering changes and your deployment pipeline's effectiveness.

## Key Metrics

- **Basic Lead Time**: Average time from commit to deployment
- **Percentile Lead Time**: 50th, 75th, or 95th percentile of lead times (more robust to outliers)
- **DORA Performance Ratings**:
  - Elite: Less than 1 hour
  - High: Between 1 day and 1 week
  - Medium: Between 1 week and 1 month
  - Low: Between 1 month and six months

## Using the Tools

### Script 1: Basic Lead Time Calculation

```bash
rails runner script/calculate_lead_time.rb [DAYS] [PERCENTILE] [save]
```

**Parameters**:
- `DAYS`: Number of days to look back (default: 30)
- `PERCENTILE`: Optional percentile to calculate (50, 75, 95)
- `save`: Add "save" to persist the results to the database

**Example**:
```bash
rails runner script/calculate_lead_time.rb 30 75
```

### Script 2: Comprehensive Lead Time Analysis

```bash
rails runner script/lead_time_analysis.rb
```

This script provides a comprehensive analysis of lead time metrics across multiple time periods (7, 30, 90 days) and calculates different percentiles for a complete picture of your delivery performance.

### Script 3: Check Deployment-Related Metrics

```bash
rails runner script/check_deployment_events.rb
```

This script analyzes your database for deployment-related metrics, including lead time metrics, and presents a summary of what's available.

### Script 4: Generate Test Metrics (for development/testing)

```bash
rails runner script/create_lead_time_metrics.rb
```

This script creates sample lead time metrics for testing and development purposes.

## How Metrics Are Collected

The system collects lead time metrics through GitHub webhook events:

1. **Deployment Creation**: `github.deployment` webhook
2. **Deployment Completion**: `github.deployment_status` webhook with `state: "success"`
3. **Lead Time Calculation**: The time difference between deployment creation and successful completion

## Troubleshooting

If you're not seeing lead time metrics:

1. Ensure your GitHub webhook events include both `deployment` and `deployment_status` events
2. Check that deployments have valid timestamps (`created_at` and `updated_at` fields)
3. Verify the GitHub webhook delivery includes the proper `X-GitHub-Event` header
4. Run `script/check_deployment_events.rb` to diagnose any issues with metrics collection

## Extending or Customizing

To modify how lead time is calculated:

1. Edit `app/core/use_cases/calculate_lead_time.rb` to change the calculation logic
2. Edit `app/core/domain/classifiers/github_event_classifier.rb` to change how webhook events are processed
3. Update the DORA rating thresholds by modifying the `determine_dora_rating` method in `calculate_lead_time.rb` 