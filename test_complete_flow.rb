#!/usr/bin/env ruby
# frozen_string_literal: true

puts "===== COMPLETE TEST OF DIRECTORY AND FILETYPE METRICS FLOW ====="

# Step 1: Generate test metrics
puts "\n1. GENERATING TEST METRICS"
event = Domain::Event.new(
  name: "github.push",
  source: "test_flow",
  data: {
    repository: { name: "test-repo" },
    commits: [
      {
        message: "test commit 1",
        added: ["app/controllers/test_controller.rb", "app/models/test_model.rb"],
        modified: ["config/routes.rb"],
        removed: []
      },
      {
        message: "test commit 2",
        added: ["app/views/test.html.erb", "public/images/test.png"],
        modified: ["README.md"],
        removed: ["tmp/old_file.txt"]
      }
    ]
  }
)

extractor = Domain::Extractors::DimensionExtractor.new
classifier = Domain::Classifiers::GithubEventClassifier.new(extractor)
result = classifier.classify(event)
metrics = result[:metrics]

puts "Generated #{metrics.size} metrics"

# Step 2: Save metrics to the database
puts "\n2. SAVING METRICS TO DATABASE"
repository = DependencyContainer.resolve(:metric_repository)

metrics.each do |metric_hash|
  metric = Domain::Metric.new(
    name: metric_hash[:name],
    value: metric_hash[:value],
    source: metric_hash[:dimensions][:source],
    dimensions: metric_hash[:dimensions],
    timestamp: Time.current
  )

  repository.save_metric(metric)
end

# Step 3: Run the aggregation jobs
puts "\n3. RUNNING AGGREGATION JOBS"
job = MetricAggregationJob.new

puts "Running 5min aggregation..."
job.perform("5min")

puts "Running daily aggregation..."
job.perform("daily")

# Step 4: Verify the metrics in the database
puts "\n4. VERIFYING METRICS IN DATABASE"

# Directory metrics
dir_metrics = DomainMetric.where("name = ? AND dimensions @> ?",
                                 "github.push.directory_changes.daily",
                                 { source: "test_flow" }.to_json)
puts "Found #{dir_metrics.count} directory daily metrics:"
dir_metrics.each do |m|
  puts "- #{m.dimensions['directory']}: #{m.value}"
end

# File type metrics
file_metrics = DomainMetric.where("name = ? AND dimensions @> ?",
                                  "github.push.filetype_changes.daily",
                                  { source: "test_flow" }.to_json)
puts "\nFound #{file_metrics.count} filetype daily metrics:"
file_metrics.each do |m|
  puts "- #{m.dimensions['filetype']}: #{m.value}"
end

# Step 5: Check if controller can use these metrics
puts "\n5. TESTING CONTROLLER WITH METRICS"
controller = Dashboards::CommitMetricsController.new
controller.instance_variable_set(:@days, 30)

metrics = controller.send(:fetch_commit_metrics, 30)

puts "Directory hotspots from controller:"
if metrics[:directory_hotspots].empty?
  puts "No directory hotspots found"
else
  metrics[:directory_hotspots].each do |dir|
    puts "- #{dir[:directory]}: #{dir[:count]}"
  end
end

puts "\nFile extension hotspots from controller:"
if metrics[:file_extension_hotspots].empty?
  puts "No file extension hotspots found"
else
  metrics[:file_extension_hotspots].each do |file|
    puts "- #{file[:extension]}: #{file[:count]}"
  end
end

puts "\n===== TEST COMPLETE ====="
