#!/usr/bin/env ruby
# frozen_string_literal: true

# This script checks for GitHub deployment status metrics in the database
# Run with: rails runner script/check_deployment_status_metrics.rb

puts "🔍 Checking for GitHub deployment status metrics in the database..."
puts "=" * 80

# Get access to the metric repository
metric_repository = DependencyContainer.resolve(:metric_repository)

# Define time period to check (30 days)
time_period = 30
start_time = time_period.days.ago

# Get metrics related to deployment status
deployment_status_metrics = metric_repository.list_metrics(
  name: "github.deployment_status.total",
  start_time: start_time
)

# Get all metrics with names starting with github.deployment_status
all_status_metrics = []
["success", "failure", "error", "inactive", "queued", "pending", "in_progress"].each do |state|
  metrics = metric_repository.list_metrics(
    name: "github.deployment_status.#{state}",
    start_time: start_time
  )
  all_status_metrics.concat(metrics)
end

# Print the results
puts "\n📊 DEPLOYMENT STATUS METRICS:"
puts "-" * 80
puts format("%-35s | %10s | %s", "METRIC NAME", "COUNT", "SAMPLE TIMESTAMP")
puts "-" * 80

if deployment_status_metrics.any?
  puts format("%-35s | %10d | %s", "github.deployment_status.total", deployment_status_metrics.count,
              deployment_status_metrics.first.timestamp)

  # Show dimensions of first metric as sample
  if deployment_status_metrics.first.dimensions.any?
    formatted_dimensions = deployment_status_metrics.first.dimensions.inspect
    puts "  └─ Sample dimensions: #{formatted_dimensions}"
  end
else
  puts format("%-35s | %10d | %s", "github.deployment_status.total", 0, "N/A")
end

# List all the status-specific metrics
["success", "failure", "error", "inactive", "queued", "pending", "in_progress"].each do |state|
  metrics = all_status_metrics.select { |m| m.name == "github.deployment_status.#{state}" }

  if metrics.any?
    puts format("%-35s | %10d | %s", "github.deployment_status.#{state}", metrics.count, metrics.first.timestamp)

    # Show dimensions of first metric as sample
    if metrics.first.dimensions.any?
      formatted_dimensions = metrics.first.dimensions.inspect
      puts "  └─ Sample dimensions: #{formatted_dimensions}"
    end
  else
    puts format("%-35s | %10d | %s", "github.deployment_status.#{state}", 0, "N/A")
  end
end

puts "\n🔍 CHECKING RAW DATABASE ENTRIES:"
puts "-" * 80

# Get a database connection to run a direct query
ActiveRecord::Base.connection_pool.with_connection do |conn|
  # Query all metrics with names starting with github.deployment_status
  sql = "SELECT name, COUNT(*) as count FROM metrics WHERE name LIKE 'github.deployment_status.%' GROUP BY name"
  result = conn.exec_query(sql)

  if result.any?
    puts "Found #{result.count} different deployment status metric types in database:"
    result.each do |row|
      puts "  - #{row['name']}: #{row['count']} records"
    end
  else
    puts "No deployment status metrics found in the database."
  end
end

puts "\n🧪 CHECKING GITHUB_EVENT_CLASSIFIER CODE:"
puts "-" * 80

begin
  # Create a GithubEventClassifier instance to check its behavior
  github_classifier = Domain::Classifiers::GithubEventClassifier.new

  # Create a sample deployment status webhook payload
  deployment_status_payload = {
    "action" => "created",
    "deployment_status" => {
      "state" => "success",
      "environment" => "production"
    },
    "deployment" => {
      "environment" => "production",
      "ref" => "main"
    },
    "repository" => {
      "full_name" => "acme/test-repo"
    }
  }

  # Create a sample event
  event = Domain::Event.new(
    name: "github.deployment_status",
    source: "github",
    data: deployment_status_payload,
    timestamp: Time.now
  )

  # Classify the event
  classification = github_classifier.classify(event)

  puts "GitHub classifier generated #{classification[:metrics].size} metrics:"
  classification[:metrics].each_with_index do |metric, index|
    puts "  #{index + 1}. Name: #{metric[:name]}, Value: #{metric[:value]}"
    puts "     Dimensions: #{metric[:dimensions].inspect}"
  end
rescue StandardError => e
  puts "Error testing classifier: #{e.message}"
end
