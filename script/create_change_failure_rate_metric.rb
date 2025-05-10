#!/usr/bin/env ruby
# frozen_string_literal: true

# This script creates a DORA change failure rate metric based on existing deployment status metrics
# Run with: rails runner script/create_change_failure_rate_metric.rb

puts "🔧 Creating DORA change failure rate metric..."
puts "=" * 80

# Get access to the metric repository
metric_repository = DependencyContainer.resolve(:metric_repository)

# Define time period (30 days)
time_period = 30
start_time = time_period.days.ago

# Successful deployments
successful_deployments = metric_repository.list_metrics(
  name: "github.deployment_status.success",
  start_time: start_time
)

puts "Found #{successful_deployments.count} successful deployments"

# Failed deployments
failed_deployments = metric_repository.list_metrics(
  name: "github.deployment_status.failure",
  start_time: start_time
)

puts "Found #{failed_deployments.count} failed deployments"

# Calculate raw change failure rate
total_deployments = successful_deployments.count + failed_deployments.count
failed_count = failed_deployments.count
failure_rate = total_deployments > 0 ? (failed_count.to_f / total_deployments) * 100 : 0

puts "\n📊 CALCULATING CHANGE FAILURE RATE:"
puts "-" * 80
puts "Total deployments: #{total_deployments}"
puts "Failed deployments: #{failed_count}"
puts "Change failure rate: #{failure_rate.round(2)}%"

# Create the DORA metric
if total_deployments > 0
  # Create metric
  metric = Domain::Metric.new(
    name: "dora.change_failure_rate",
    value: failure_rate.round(2),
    source: "calculated",
    dimensions: {
      "period_days" => time_period.to_s,
      "failures" => failed_count.to_s,
      "deployments" => total_deployments.to_s
    },
    timestamp: Time.now
  )

  # Save through the repository
  puts "\n💾 SAVING DORA CHANGE FAILURE RATE METRIC:"
  puts "-" * 80

  begin
    metric_repository.save_metric(metric)
    puts "✅ DORA change failure rate metric saved successfully!"
    puts "Value: #{metric.value}%, Dimensions: #{metric.dimensions.inspect}"
  rescue StandardError => e
    puts "❌ Error saving metric: #{e.message}"
  end
else
  puts "❌ No deployments found, not creating a metric"
end
