#!/usr/bin/env ruby
# frozen_string_literal: true

# This script manually creates deployment status metrics for testing
# Run with: rails runner script/create_deployment_status_metrics.rb

require "time"

puts "🛠️  Creating deployment status metrics for testing..."
puts "==============================================="

# Get a reference to the metric repository
metric_repo = DependencyContainer.resolve(:metric_repository)

# Create test deployment metrics
puts "\nCreating deployment status metrics..."

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
    timestamp: Time.now - (i * 3600),
    source: "github",
    dimensions: {
      environment: environments.sample,
      repository: repo_names.sample,
      organization: org_names.sample
    }
  )

  metric_repo.save_metric(success_metric)
  puts "✅ Created success metric ##{i}"

  # Also create the total metric that would normally be created
  total_metric = Domain::Metric.new(
    name: "github.deployment_status.total",
    value: 1,
    timestamp: Time.now - (i * 3600),
    source: "github",
    dimensions: {
      state: "success",
      environment: environments.sample,
      repository: repo_names.sample,
      organization: org_names.sample
    }
  )

  metric_repo.save_metric(total_metric)
  puts "✅ Created total metric ##{i}"
end

# Create some deployment metrics too for completeness
(1..5).each do |i|
  deployment_metric = Domain::Metric.new(
    name: "github.deployment.total",
    value: 1,
    timestamp: Time.now - ((i * 3600) + 1800), # Offset by 30 minutes before the status
    source: "github",
    dimensions: {
      environment: environments.sample,
      repository: repo_names.sample,
      organization: org_names.sample
    }
  )

  metric_repo.save_metric(deployment_metric)
  puts "✅ Created deployment metric ##{i}"
end

puts "\n✅ Created 15 metrics (5 success, 5 total, 5 deployment)"
puts "Run \"rails runner 'MetricAggregationJob.new.perform(\\'daily\\')'\" to aggregate metrics"
puts "Then run \"script/check_deployment_status_metrics.rb\" to verify"
