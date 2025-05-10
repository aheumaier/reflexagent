#!/usr/bin/env ruby
# frozen_string_literal: true

# This script debugs the change failure rate calculation
# Run with: rails runner script/debug_change_failure_rate.rb

puts "🔍 Debugging change failure rate calculation..."
puts "=" * 80

# Get access to the metric repository
metric_repository = DependencyContainer.resolve(:metric_repository)

# Create an instance of the use case
calculate_change_failure_rate = UseCases::CalculateChangeFailureRate.new(
  storage_port: metric_repository,
  logger_port: Rails.logger
)

# Define time period (30 days)
time_period = 30
start_time = time_period.days.ago

# Check for DORA metrics first
puts "\n📊 CHECKING DORA CHANGE FAILURE RATE METRICS:"
puts "-" * 80

dora_metric_types = [
  "dora.change_failure_rate",
  "dora.change_failure_rate.hourly",
  "dora.change_failure_rate.5min"
]

dora_metric_types.each do |metric_type|
  metrics = metric_repository.list_metrics(
    name: metric_type,
    start_time: start_time
  )
  puts "#{metric_type}: #{metrics.count} metrics"
end

# Now check the raw deployment and failure metrics
puts "\n📊 CHECKING RAW DEPLOYMENT AND FAILURE METRICS:"
puts "-" * 80

# Successful deployments
successful_deployments = metric_repository.list_metrics(
  name: "github.deployment_status.success",
  start_time: start_time
)

puts "github.deployment_status.success: #{successful_deployments.count} metrics"

# Failed deployments
failed_deployments = metric_repository.list_metrics(
  name: "github.deployment_status.failure",
  start_time: start_time
)

puts "github.deployment_status.failure: #{failed_deployments.count} metrics"

# Calculate raw change failure rate
total_deployments = successful_deployments.count + failed_deployments.count
failure_rate = total_deployments > 0 ? (failed_deployments.count.to_f / total_deployments) * 100 : 0

puts "\n📊 RAW CHANGE FAILURE RATE CALCULATION:"
puts "-" * 80
puts "Total deployments: #{total_deployments}"
puts "Failed deployments: #{failed_deployments.count}"
puts "Success deployments: #{successful_deployments.count}"
puts "Change failure rate: #{failure_rate.round(2)}%"

# Call the use case to calculate change failure rate
puts "\n📊 CHANGE FAILURE RATE FROM USE CASE:"
puts "-" * 80
result = calculate_change_failure_rate.call(time_period: time_period)
puts "Result: #{result.inspect}"

# Check if there are any deployment incidents that might be used for calculation
puts "\n📊 CHECKING FOR DEPLOYMENT INCIDENTS:"
puts "-" * 80

incident_metrics = metric_repository.list_metrics(
  name: "github.ci.deploy.incident",
  start_time: start_time
)

puts "github.ci.deploy.incident: #{incident_metrics.count} metrics"

puts "\n✅ Debug complete!"
