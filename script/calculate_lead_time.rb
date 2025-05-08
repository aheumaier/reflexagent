#!/usr/bin/env ruby
# frozen_string_literal: true

# This script manually calculates lead time metrics from the deployment_status metrics
# Run with: rails runner script/calculate_lead_time.rb

puts "⏱️  Calculating lead time metrics..."
puts "=================================="

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

  puts "Period: #{days} days"
  puts "  Lead Time: #{lead_time_hours.round(2)} hours"
  puts "  DORA Rating: #{lead_time_rating}"

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

puts "\n✅ Lead time calculations complete"
puts "Run 'rails runner script/check_deployment_events.rb' to see all metrics"
