#!/usr/bin/env ruby
# frozen_string_literal: true

# Check for deployment events and metrics in the database
# Run with: rails runner script/check_deployment_events.rb

puts "🔍 Checking for deployment-related events and metrics in the database..."
puts "=" * 80

# Get access to the metric repository
metric_repository = DependencyContainer.resolve(:metric_repository)

# Define time period to check (30 days)
time_period = 30
start_time = time_period.days.ago

# Array of metric names to check
deployment_metric_names = [
  "github.deployment.total",
  "github.deployment_status.success",
  "github.deployment_status.failure",
  "github.ci.deploy.completed",
  "github.ci.deploy.failed",
  "github.ci.lead_time"
]

# Check each type of metric
puts "\n📊 DEPLOYMENT METRICS:"
puts "-" * 80
puts format("%-35s | %10s | %s", "METRIC NAME", "COUNT", "SAMPLE TIMESTAMP")
puts "-" * 80

deployment_metric_names.each do |metric_name|
  metrics = metric_repository.list_metrics(
    name: metric_name,
    start_time: start_time
  )

  if metrics.any?
    sample_timestamp = metrics.first.timestamp.strftime("%Y-%m-%d %H:%M:%S")
    puts format("%-35s | %10d | %s", metric_name, metrics.count, sample_timestamp)

    # Show sample dimensions for first record
    puts "  └─ Sample dimensions: #{metrics.first.dimensions.inspect}" if metrics.first.dimensions.any?
  else
    puts format("%-35s | %10d | %s", metric_name, 0, "N/A")
  end
end

# Check for lead time metrics specifically
puts "\n⏱️ LEAD TIME METRICS DETAILS:"
puts "-" * 80

lead_time_metrics = metric_repository.list_metrics(
  name: "github.ci.lead_time",
  start_time: start_time
)

if lead_time_metrics.any?
  puts "Found #{lead_time_metrics.count} lead time metrics"

  # Calculate average lead time in hours
  lead_time_values = lead_time_metrics.map { |m| m.value / 3600.0 } # Convert seconds to hours
  avg_lead_time = lead_time_values.sum / lead_time_values.size

  puts "Average lead time: #{avg_lead_time.round(2)} hours"
  puts "Min lead time: #{lead_time_values.min.round(2)} hours"
  puts "Max lead time: #{lead_time_values.max.round(2)} hours"

  # List some sample records
  puts "\nSample lead time metrics (up to 5):"
  lead_time_metrics.take(5).each_with_index do |metric, i|
    puts "#{i + 1}. Value: #{(metric.value / 3600.0).round(2)} hours, Timestamp: #{metric.timestamp.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "   Dimensions: #{metric.dimensions.inspect}"
  end
else
  puts "No lead time metrics found in the database."
  puts "You may need to run the demo_events.rb script to generate sample events."
end

puts "\n🔄 DORA METRICS:"
puts "-" * 80

dora_metrics = metric_repository.list_metrics(
  name: "dora.lead_time",
  start_time: start_time
)

if dora_metrics.any?
  puts "Found #{dora_metrics.count} DORA lead time metrics"

  # List some sample records
  puts "\nSample DORA metrics (up to 5):"
  dora_metrics.take(5).each_with_index do |metric, i|
    puts "#{i + 1}. Value: #{metric.value.round(2)} hours, Rating: #{metric.dimensions['rating']}, Period: #{metric.dimensions['period_days']} days"
    puts "   Recorded at: #{metric.timestamp.strftime('%Y-%m-%d %H:%M:%S')}"
  end
else
  puts "No DORA lead time metrics found in the database."
end

puts "=" * 80
puts "Try running 'rails runner bin/demo_events.rb' to generate sample events" if lead_time_metrics.empty?
