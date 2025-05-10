#!/usr/bin/env ruby
# frozen_string_literal: true

# This script checks github.ci.deploy.completed metrics in the database
# Run with: rails runner script/check_deploy_completed_metrics.rb

puts "🔍 Checking github.ci.deploy.completed metrics..."
puts "=" * 80

# Get access to the metric repository
metric_repository = DependencyContainer.resolve(:metric_repository)

# Define time period (30 days)
time_period = 30
start_time = time_period.days.ago

# Get deployment success metrics
deploy_completed_metrics = metric_repository.list_metrics(
  name: "github.ci.deploy.completed",
  start_time: start_time
)

puts "\n📊 GITHUB.CI.DEPLOY.COMPLETED METRICS:"
puts "-" * 80
puts "Total count: #{deploy_completed_metrics.count}"

# Group by day to see distribution
deploy_by_day = deploy_completed_metrics.group_by do |metric|
  metric.timestamp.strftime("%Y-%m-%d")
end

puts "\nDeployments by day:"
deploy_by_day.each do |day, metrics|
  puts "  #{day}: #{metrics.count} deployments"
end

# Group by repository
deploy_by_repo = deploy_completed_metrics.group_by do |metric|
  metric.dimensions["repository"] || "unknown"
end

puts "\nDeployments by repository:"
deploy_by_repo.each do |repo, metrics|
  puts "  #{repo}: #{metrics.count} deployments"
end

# Compare with deployment_status.success metrics
deployment_status_metrics = metric_repository.list_metrics(
  name: "github.deployment_status.success",
  start_time: start_time
)

puts "\n📊 COMPARISON WITH GITHUB.DEPLOYMENT_STATUS.SUCCESS:"
puts "-" * 80
puts "github.ci.deploy.completed: #{deploy_completed_metrics.count} metrics"
puts "github.deployment_status.success: #{deployment_status_metrics.count} metrics"

# Check for any potential duplicates (same timestamp and repository)
puts "\nChecking for potential duplicate deployments..."
all_deployments = (deploy_completed_metrics + deployment_status_metrics).sort_by(&:timestamp)

duplicates = []
previous = nil
all_deployments.each do |metric|
  if previous &&
     previous.timestamp == metric.timestamp &&
     previous.dimensions["repository"] == metric.dimensions["repository"]
    duplicates << [previous, metric]
  end
  previous = metric
end

if duplicates.any?
  puts "Found #{duplicates.size} potential duplicate deployments:"
  duplicates.each do |pair|
    puts "  #{pair[0].name} and #{pair[1].name} - #{pair[0].timestamp} - #{pair[0].dimensions['repository']}"
  end
else
  puts "No duplicates found."
end

puts "\n✅ Check complete!"
