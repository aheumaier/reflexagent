#!/usr/bin/env ruby
# frozen_string_literal: true

# This script manually creates lead time metrics for testing
# Run with: rails runner script/create_lead_time_metrics.rb

require "time"

puts "🛠️  Creating lead time metrics for testing..."
puts "========================================"

# Get a reference to the metric repository
metric_repo = DependencyContainer.resolve(:metric_repository)

# Sample metadata for all metrics
repo_names = ["acme/frontend", "acme/backend", "acme/auth-service"]
org_names = ["acme"]
environments = ["production"]

puts "\nCreating lead time metrics..."

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

# For each lead time value, create multiple metrics
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

total_metrics = lead_times.length * 2.5 # Average of 2.5 metrics per lead time value
puts "\n✅ Created #{total_metrics.to_i} lead time metrics"
puts "Run \"rails runner script/calculate_lead_time.rb\" to see the calculated metrics"
