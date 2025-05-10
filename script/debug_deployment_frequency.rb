#!/usr/bin/env ruby
# frozen_string_literal: true

# This script debugs the deployment frequency calculation for the last 7 days
# Run with: rails runner script/debug_deployment_frequency.rb

puts "🔍 Debugging deployment frequency calculation..."
puts "=" * 80

# Get access to the metric repository
metric_repository = DependencyContainer.resolve(:metric_repository)

# Create an instance of the use case
calculate_deployment_frequency = UseCases::CalculateDeploymentFrequency.new(
  storage_port: metric_repository,
  logger_port: Rails.logger
)

# Define time period (7 days)
time_period = 7
start_time = time_period.days.ago

puts "\n📊 CHECKING SUCCESS DEPLOYMENT METRICS:"
puts "-" * 80

# Get deployment status success metrics
deployment_status_metrics = metric_repository.list_metrics(
  name: "github.deployment_status.success",
  start_time: start_time
)

puts "Found #{deployment_status_metrics.count} github.deployment_status.success metrics"
deployment_status_metrics.each_with_index do |metric, index|
  puts "  #{index + 1}. Timestamp: #{metric.timestamp}, Repository: #{metric.dimensions['repository']}"
end

# Call the use case to calculate deployment frequency
puts "\n📊 CALCULATING DEPLOYMENT FREQUENCY:"
puts "-" * 80
result = calculate_deployment_frequency.call(time_period: time_period)
puts "Result: #{result.inspect}"

puts "\n📊 METRICS BREAKDOWN BY TYPE:"
puts "-" * 80

# Check all types of deployment metrics
metric_types = [
  "dora.deployment_frequency",
  "dora.deployment_frequency.hourly",
  "dora.deployment_frequency.5min",
  "github.ci.deploy.completed",
  "github.deployment_status.success",
  "github.deployment.total"
]

metric_types.each do |metric_type|
  metrics = metric_repository.list_metrics(
    name: metric_type,
    start_time: start_time
  )
  puts "#{metric_type}: #{metrics.count} metrics"
end

puts "\n✅ Debug complete!"
