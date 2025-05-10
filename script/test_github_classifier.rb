#!/usr/bin/env ruby
# frozen_string_literal: true

# This script tests the GitHub event classifier to see if it generates the expected metrics
# Run with: rails runner script/test_github_classifier.rb

puts "🔍 Testing GitHub Event Classifier commit date processing..."
puts "=" * 80

# Get a GitHub push event
db_event = DomainEvent.where(event_type: "github.push.created").order(created_at: :desc).first

if db_event.nil?
  puts "❌ No GitHub push events found!"
  exit
end

puts "📊 ANALYZING EVENT:"
puts "-" * 80
puts "DB Event ID: #{db_event.id}"
puts "Created: #{db_event.created_at}"
puts "Payload type: #{db_event.payload.class}"

# Examine the payload structure
puts "\n📦 PAYLOAD STRUCTURE:"
puts "-" * 80

puts "Top-level keys: #{db_event.payload.keys.inspect}"
puts "Repository: #{db_event.payload['repository'] ? db_event.payload['repository']['full_name'] : 'Not found'}"
puts "Ref: #{db_event.payload['ref']}"

# Convert payload to data to match what the classifier expects
data = {}
db_event.payload.each do |k, v|
  data[k.to_sym] = v
end

# Extract and display commit details
commits = data[:commits] || []
puts "\n📝 COMMIT DETAILS:"
puts "-" * 80
puts "Commits array type: #{commits.class}"
puts "Commit count: #{commits.size}"

commits.each_with_index do |commit, i|
  puts "\nCommit #{i + 1}:"
  puts "  ID: #{commit['id']}"
  puts "  Author: #{commit['author']['name']}" if commit["author"]
  puts "  Message: #{commit['message']}"
  puts "  Timestamp: #{commit['timestamp']}"

  # Check if symbols or strings are used for keys
  puts "  Uses symbol keys: #{commit.key?(:id) && commit.key?(:timestamp)}"
  puts "  Uses string keys: #{commit.key?('id') && commit.key?('timestamp')}"
end

# Convert to a Domain::Event since the classifier expects that
event = Domain::Event.new(
  id: db_event.id.to_s,
  name: "github.push", # The classifier splits by dots, so use github.push
  source: "github",
  data: data, # Use the symbolized keys data
  timestamp: db_event.created_at
)

# Get dependencies for classifier
puts "\n🔧 INITIALIZING CLASSIFIER:"
puts "-" * 80

extractor = begin
  DependencyContainer.resolve(:dimension_extractor)
rescue StandardError
  nil
end
if extractor.nil?
  puts "Creating new dimension extractor"
  extractor = Domain::Extractors::DimensionExtractor.new
end

classifier = Domain::Classifiers::GithubEventClassifier.new(extractor)
puts "Classifier initialized: #{classifier.class.name}"

# Process event with classifier
puts "\n🔬 PROCESSING EVENT THROUGH CLASSIFIER:"
puts "-" * 80

result = classifier.classify(event)
puts "Generated #{result[:metrics].size} metrics"

# Show all metrics
puts "\n📊 ALL GENERATED METRICS:"
puts "-" * 80
result[:metrics].each_with_index do |metric, i|
  puts "Metric #{i + 1}: #{metric[:name]}"
  puts "  Value: #{metric[:value]}"
  puts "  Dimensions: #{metric[:dimensions].inspect}"
end

# Filter and display commit volume metrics
daily_metrics = result[:metrics].select { |m| m[:name] == "github.commit_volume.daily" }
puts "\n📈 COMMIT VOLUME DAILY METRICS (#{daily_metrics.size}):"
puts "-" * 80

if daily_metrics.empty?
  puts "❌ No github.commit_volume.daily metrics generated!"
else
  daily_metrics.each_with_index do |metric, i|
    puts "Metric #{i + 1}:"
    puts "  Name: #{metric[:name]}"
    puts "  Value: #{metric[:value]}"
    puts "  Dimensions:"
    metric[:dimensions].each do |key, value|
      puts "    #{key}: #{value}"
    end
    puts "  Timestamp: #{metric[:timestamp]}"
  end
end

# Simulate the process_commits method manually
puts "\n🔧 MANUAL PROCESS_COMMITS SIMULATION:"
puts "-" * 80

commits_by_date = {}
commits.each do |commit|
  # For string keys
  timestamp_str = commit["timestamp"]

  if timestamp_str.present?
    begin
      commit_date = Time.parse(timestamp_str).strftime("%Y-%m-%d")
      commits_by_date[commit_date] ||= 0
      commits_by_date[commit_date] += 1
      puts "✅ Added commit (string keys) to date #{commit_date}"
    rescue ArgumentError
      puts "❌ Error parsing timestamp (string keys) '#{timestamp_str}'"
    end
  end

  # For symbol keys
  timestamp_sym = commit[:timestamp]

  next unless timestamp_sym.present?

  begin
    commit_date = Time.parse(timestamp_sym).strftime("%Y-%m-%d")
    puts "✅ Added commit (symbol keys) to date #{commit_date}"
  rescue ArgumentError
    puts "❌ Error parsing timestamp (symbol keys) '#{timestamp_sym}'"
  end
end

puts "\nFinal commits_by_date: #{commits_by_date.inspect}"
