#!/usr/bin/env ruby
# frozen_string_literal: true

# This script fixes deployment status metrics by properly creating them in the database
# Run with: rails runner script/fix_deployment_status_events.rb

puts "🔧 Fixing Deployment Status Metrics"
puts "=================================="

# Clear existing incorrect metrics first
puts "\n1️⃣ Checking for existing deployment status metrics..."
count = DomainMetric.where("name LIKE ?", "%deployment_status%").count
puts "Found #{count} existing deployment status metrics"

puts "\n2️⃣ Creating proper deployment status metrics..."

# Get a reference to the metric repository
metric_repo = DependencyContainer.resolve(:metric_repository)

# Sample metadata for metrics
repo_names = ["acme/frontend", "acme/backend", "acme/auth-service"]
org_names = ["acme"]
environments = ["production", "staging"]
states = ["success", "failure", "in_progress"]

# Create deployment status metrics
(1..10).each do |i|
  # Pick random values
  repo_name = repo_names.sample
  org_name = org_names.sample
  environment = environments.sample
  state = states.sample

  # Create base timestamp (newer metrics first)
  timestamp = Time.now - (i * 3600) # hours

  # Create a deployment status metric with the state
  status_metric = Domain::Metric.new(
    name: "github.deployment_status.#{state}",
    value: 1,
    timestamp: timestamp,
    source: "github",
    dimensions: {
      environment: environment,
      repository: repo_name,
      organization: org_name
    }
  )

  metric_repo.save_metric(status_metric)
  puts "✅ Created #{state} metric for #{repo_name} in #{environment}"

  # Also create the total metric
  total_metric = Domain::Metric.new(
    name: "github.deployment_status.total",
    value: 1,
    timestamp: timestamp,
    source: "github",
    dimensions: {
      state: state,
      environment: environment,
      repository: repo_name,
      organization: org_name
    }
  )

  metric_repo.save_metric(total_metric)
  puts "✅ Created total metric for #{repo_name} in #{environment} (state: #{state})"

  # If the state is success or failure, also create CI deploy metrics
  next unless ["success", "failure"].include?(state)

  ci_status = state == "success" ? "completed" : "failed"

  # CI deploy total metric
  ci_total_metric = Domain::Metric.new(
    name: "github.ci.deploy.total",
    value: 1,
    timestamp: timestamp,
    source: "github",
    dimensions: {
      environment: environment,
      repository: repo_name,
      organization: org_name
    }
  )

  metric_repo.save_metric(ci_total_metric)
  puts "✅ Created CI deploy total metric for #{repo_name} in #{environment}"

  # CI deploy status metric
  ci_status_metric = Domain::Metric.new(
    name: "github.ci.deploy.#{ci_status}",
    value: 1,
    timestamp: timestamp,
    source: "github",
    dimensions: {
      environment: environment,
      repository: repo_name,
      organization: org_name
    }
  )

  metric_repo.save_metric(ci_status_metric)
  puts "✅ Created CI deploy #{ci_status} metric for #{repo_name} in #{environment}"

  # If success, add lead time metric
  next unless state == "success"

  # Random lead time between 5 minutes and 2 hours
  lead_time = rand(300..7200)

  lead_time_metric = Domain::Metric.new(
    name: "github.ci.lead_time",
    value: lead_time,
    timestamp: timestamp,
    source: "github",
    dimensions: {
      environment: environment,
      repository: repo_name,
      organization: org_name
    }
  )

  metric_repo.save_metric(lead_time_metric)
  puts "✅ Created lead time metric (#{lead_time / 60.0} min) for #{repo_name} in #{environment}"
end

# Run the metrics job to aggregate the new metrics
puts "\n3️⃣ Running the MetricAggregationJob to aggregate metrics..."
begin
  result = MetricAggregationJob.new.perform("daily")
  puts "✅ MetricAggregationJob completed successfully"
rescue StandardError => e
  puts "❌ Error running MetricAggregationJob: #{e.message}"
end

# Verify the metrics were created
puts "\n4️⃣ Verifying metrics were created..."
count_after = DomainMetric.where("name LIKE ?", "%deployment_status%").count
puts "Now have #{count_after} deployment status metrics (added #{count_after - count})"

puts "\n✅ Fix complete!"
puts "Run 'rails runner script/check_deployment_status_metrics.rb' to verify the metrics"
