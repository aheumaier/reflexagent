#!/usr/bin/env ruby
# frozen_string_literal: true

# This script tests the GitHub event classifier to see if it properly generates
# directory and filetype metrics for a sample push event

# Create a sample GitHub push event
event = Domain::Event.new(
  name: "github.push",
  source: "test_run",
  data: {
    repository: { name: "test-repo" },
    commits: [
      {
        message: "test commit",
        added: ["app/test.rb", "app/models/test.rb"],
        modified: ["config/routes.rb"],
        removed: []
      }
    ]
  }
)

# Create an extractor and classifier
extractor = Domain::Extractors::DimensionExtractor.new
classifier = Domain::Classifiers::GithubEventClassifier.new(extractor)

# Classify the event
result = classifier.classify(event)
metrics = result[:metrics]

puts "Generated #{metrics.size} metrics"

# Save metrics to the database
repository = DependencyContainer.resolve(:metric_repository)
saved_metrics = []

metrics.each do |metric_hash|
  metric = Domain::Metric.new(
    name: metric_hash[:name],
    value: metric_hash[:value],
    source: metric_hash[:dimensions][:source],
    dimensions: metric_hash[:dimensions],
    timestamp: Time.current
  )

  saved_metric = repository.save_metric(metric)
  saved_metrics << saved_metric

  puts "Saved metric: #{saved_metric.name} (ID: #{saved_metric.id})"
end

puts "\nSaved #{saved_metrics.size} metrics to the database"

# Run the metric aggregation jobs for different time periods
puts "\nRunning 5min metric aggregation job..."
job = MetricAggregationJob.new
metrics_count_5min = job.perform("5min")
puts "Aggregated #{metrics_count_5min} metrics for 5min period"

puts "\nRunning daily metric aggregation job..."
metrics_count_daily = job.perform("daily")
puts "Aggregated #{metrics_count_daily} metrics for daily period"

# Verify that the aggregates were created
minute_directory_metrics = DomainMetric.where("name LIKE ?", "github.push.directory_changes.5min").count
minute_filetype_metrics = DomainMetric.where("name LIKE ?", "github.push.filetype_changes.5min").count
daily_directory_metrics = DomainMetric.where("name LIKE ?", "github.push.directory_changes.daily").count
daily_filetype_metrics = DomainMetric.where("name LIKE ?", "github.push.filetype_changes.daily").count

puts "\nVerification:"
puts "- 5min directory metrics: #{minute_directory_metrics}"
puts "- 5min filetype metrics: #{minute_filetype_metrics}"
puts "- Daily directory metrics: #{daily_directory_metrics}"
puts "- Daily filetype metrics: #{daily_filetype_metrics}"
