#!/usr/bin/env ruby
# frozen_string_literal: true

# This script provides a comprehensive test of lead time metrics
# Run with: rails runner script/test_lead_time.rb [--skip-clear]
#
# It performs the following steps:
# 1. Clears metrics and events from the database (unless --skip-clear is used)
# 2. Creates test deployment and deployment_status metrics
# 3. Creates test lead time metrics
# 4. Runs the metric aggregation job
# 5. Shows the results of all metrics

require "time"

# Check if we should skip clearing the database
skip_clear = ARGV.include?("--skip-clear")

puts "🧪 LEAD TIME METRICS TEST SCRIPT"
puts "=================================="
puts "This script will:"
puts "  1. Clear existing metrics#{' (SKIPPED)' if skip_clear}"
puts "  2. Create test deployment status metrics"
puts "  3. Create test lead time metrics"
puts "  4. Run metric aggregation"
puts "  5. Show results"
puts "=================================="

# Step 1: Clear the database
unless skip_clear
  puts "\n🗑️  STEP 1: Clearing metrics and events..."

  metrics_count = DomainMetric.count
  puts "Found #{metrics_count} metrics"

  events_count = DomainEvent.count
  puts "Found #{events_count} events"

  puts "\nDeleting all metrics..."
  DomainMetric.delete_all
  puts "✅ All metrics deleted."

  puts "\nDeleting all events..."
  DomainEvent.delete_all
  puts "✅ All events deleted."
end

# Step 2: Create test deployment status metrics
puts "\n🚀 STEP 2: Creating deployment status metrics..."

# Get a reference to the metric repository
metric_repo = DependencyContainer.resolve(:metric_repository)

# Sample metadata for all metrics
repo_names = ["acme/frontend", "acme/backend", "acme/auth-service"]
org_names = ["acme"]
environments = ["production", "staging"]

# Create some sample deployment status metrics
(1..5).each do |i|
  # Create a successful deployment status metric
  success_metric = Domain::Metric.new(
    name: "github.deployment_status.success",
    value: 1,
    source: "github",
    timestamp: Time.now - i.days,
    dimensions: {
      repository: repo_names.sample,
      environment: environments.sample,
      organization: org_names.sample
    }
  )

  metric_repo.save_metric(success_metric)
  puts "✅ Created success metric ##{i}"

  # Create a total deployment status metric
  total_metric = Domain::Metric.new(
    name: "github.deployment_status.total",
    value: 1,
    source: "github",
    timestamp: Time.now - i.days,
    dimensions: {
      state: "success",
      repository: repo_names.sample,
      environment: environments.sample,
      organization: org_names.sample
    }
  )

  metric_repo.save_metric(total_metric)
  puts "✅ Created total metric ##{i}"

  # Create a regular deployment metric
  deployment_metric = Domain::Metric.new(
    name: "github.deployment.total",
    value: 1,
    source: "github",
    timestamp: Time.now - i.days,
    dimensions: {
      source: "github",
      repository: repo_names.sample,
      organization: org_names.sample
    }
  )

  metric_repo.save_metric(deployment_metric)
  puts "✅ Created deployment metric ##{i}"
end

# Step 3: Create lead time metrics
puts "\n⏱️  STEP 3: Creating lead time metrics..."

# Create lead time metrics with a range of values
# from 30 minutes to 7 days (in seconds)
lead_times = [
  1800,        # 30 minutes
  7200,        # 2 hours
  21_600,       # 6 hours
  86_400,       # 1 day
  172_800,      # 2 days
  345_600,      # 4 days
  518_400,      # 6 days
  604_800       # 7 days
]

# For each lead time value, create metrics
lead_times.each_with_index do |seconds, index|
  # Create 2-3 metrics for each lead time value to have a good sample size
  (1..rand(2..3)).each do |i|
    metric = Domain::Metric.new(
      name: "github.ci.lead_time",
      value: seconds,
      source: "github",
      timestamp: Time.now - ((index * 86_400) + rand(3600..43_200)), # Distribute over time
      dimensions: {
        environment: environments.sample,
        repository: repo_names.sample,
        organization: org_names.sample,
        # Add some process breakdown data
        code_review_hours: (seconds * 0.4 / 3600.0).round(2).to_s,  # 40% of time in code review
        ci_hours: (seconds * 0.1 / 3600.0).round(2).to_s,           # 10% in CI
        qa_hours: (seconds * 0.2 / 3600.0).round(2).to_s,           # 20% in QA
        approval_hours: (seconds * 0.1 / 3600.0).round(2).to_s,     # 10% in approval
        deployment_hours: (seconds * 0.2 / 3600.0).round(2).to_s    # 20% in deployment
      }
    )

    metric_repo.save_metric(metric)
    lead_time_hours = (seconds / 3600.0).round(2)
    puts "✅ Created lead time metric: #{lead_time_hours} hours (##{index + 1}.#{i})"
  end
end

# Step 4: Run metric aggregation
puts "\n🔄 STEP 4: Running metric aggregation..."
MetricAggregationJob.new.perform("daily")
puts "✅ Completed metric aggregation"

# Step 5: Show results
puts "\n📊 STEP 5: Showing results..."
puts "Running lead time calculation..."

# Get required ports
metric_repository = DependencyContainer.resolve(:metric_repository)

# Create lead time use case
calculate_lead_time = UseCases::CalculateLeadTime.new(
  storage_port: metric_repository
)

# Calculate for different time periods
periods = [7, 30, 90]

# Execute the use case for each period
periods.each do |days|
  result = calculate_lead_time.call(time_period: days)

  lead_time_hours = result[:value]
  lead_time_rating = result[:rating]

  puts "\nPeriod: #{days} days"
  puts "  Lead Time: #{lead_time_hours.round(2)} hours"
  puts "  DORA Rating: #{lead_time_rating}"
  puts "  Sample size: #{result[:sample_size]} metrics"

  # Calculate percentiles separately
  p50_result = calculate_lead_time.call(time_period: days, percentile: 50)
  p75_result = calculate_lead_time.call(time_period: days, percentile: 75)
  p95_result = calculate_lead_time.call(time_period: days, percentile: 95)

  puts "  Percentiles:"
  puts "    50th: #{p50_result[:percentile] ? p50_result[:percentile][:value].round(2) : 0} hours"
  puts "    75th: #{p75_result[:percentile] ? p75_result[:percentile][:value].round(2) : 0} hours"
  puts "    95th: #{p95_result[:percentile] ? p95_result[:percentile][:value].round(2) : 0} hours"
  puts "--------------------------------"
end

puts "\n✅ LEAD TIME METRICS TEST COMPLETE"
puts "=================================="
puts "Try these additional scripts:"
puts "- script/check_deployment_events.rb   # View all deployment metrics"
puts "- script/check_deployment_status_metrics.rb  # View deployment status metrics"
puts "- script/calculate_lead_time.rb       # Calculate lead time only"
