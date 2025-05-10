#!/usr/bin/env ruby
# frozen_string_literal: true

# This script tests the GitHub event classifier with debug logging
# Run with: rails runner script/debug_commit_volume.rb

puts "🔍 Testing GitHub Event Classifier with debug logging..."
puts "=" * 80

# Set up logging to stdout
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = :debug

# Get a GitHub push event
db_event = DomainEvent.where(event_type: "github.push.created").order(created_at: :desc).first

if db_event.nil?
  puts "❌ No GitHub push events found!"
  exit
end

puts "📊 USING EVENT:"
puts "-" * 80
puts "DB Event ID: #{db_event.id}"
puts "Repository: #{db_event.payload['repository']['full_name']}"
puts "Commits: #{db_event.payload['commits'].size}"

# Convert payload to symbolized keys
data = {}
db_event.payload.each do |k, v|
  data[k.to_sym] = v
end

# Convert the commit hashes to use symbol keys
if data[:commits].is_a?(Array)
  data[:commits] = data[:commits].map do |commit|
    commit_with_symbols = {}
    commit.each do |k, v|
      commit_with_symbols[k.to_sym] = v
    end
    commit_with_symbols
  end
  puts "Converted #{data[:commits].size} commits to use symbol keys"
end

# Create Domain::Event
event = Domain::Event.new(
  id: db_event.id.to_s,
  name: "github.push",
  source: "github",
  data: data,
  timestamp: db_event.created_at
)

# Initialize classifier
extractor = begin
  DependencyContainer.resolve(:dimension_extractor)
rescue StandardError
  Domain::Extractors::DimensionExtractor.new
end
classifier = Domain::Classifiers::GithubEventClassifier.new(extractor)

puts "\n🔬 PROCESSING EVENT THROUGH CLASSIFIER WITH DEBUG LOGGING:"
puts "-" * 80

result = classifier.classify(event)

puts "\n📊 METRICS GENERATED: #{result[:metrics].size}"
puts "-" * 80

# Filter for commit volume metrics
daily_metrics = result[:metrics].select { |m| m[:name] == "github.commit_volume.daily" }
puts "Found #{daily_metrics.size} github.commit_volume.daily metrics\n"

daily_metrics.each_with_index do |metric, idx|
  puts "Metric #{idx + 1}:"
  puts "  Date: #{metric[:dimensions][:date]}"
  puts "  Value: #{metric[:value]}"
  puts "  Dimensions: #{metric[:dimensions].inspect}"
end
