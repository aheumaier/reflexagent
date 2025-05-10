#!/usr/bin/env ruby
# frozen_string_literal: true

# This script debugs the full GitHub push event processing
# Run with: rails runner script/debug_push_event_processing.rb

puts "🔍 Debugging GitHub push event processing..."
puts "=" * 80

# Enable debug logging
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = :debug

# Get a GitHub push event
db_event = DomainEvent.where(event_type: "github.push.created").order(created_at: :desc).first

if db_event.nil?
  puts "❌ No GitHub push events found!"
  exit
end

puts "📊 ANALYZING EVENT:"
puts "-" * 80
puts "Event ID: #{db_event.id}"
puts "Created: #{db_event.created_at}"
puts "Repository: #{db_event.payload['repository']['full_name']}"
puts "Ref: #{db_event.payload['ref']}"

# Create test events with string and symbol keys
# 1. String keys - original event format
string_data = db_event.payload
string_event = Domain::Event.new(
  id: "#{db_event.id}_string",
  name: "github.push",
  source: "github",
  data: string_data,
  timestamp: db_event.created_at
)

# Show string commit data
puts "\nString keys commit data:"
puts "Commit count: #{string_data['commits'] ? string_data['commits'].size : 'nil'}"
if string_data["commits"] && string_data["commits"].first
  commit = string_data["commits"].first
  puts "First commit keys: #{commit.keys.inspect}"
  puts "Timestamp: #{commit['timestamp']}"
end

# 2. Symbol keys - converted keys
symbol_data = {}
db_event.payload.each do |k, v|
  symbol_data[k.to_sym] = if v.is_a?(Hash)
                            v_hash = {}
                            v.each { |sk, sv| v_hash[sk.to_sym] = sv }
                            v_hash
                          else
                            v
                          end
end

# Deep symbolize the commits
if symbol_data[:commits].is_a?(Array)
  symbol_data[:commits] = symbol_data[:commits].map do |commit|
    if commit.is_a?(Hash)
      commit_hash = {}
      commit.each { |k, v| commit_hash[k.to_sym] = v }
      commit_hash
    else
      commit
    end
  end
end

# Show symbol commit data
puts "\nSymbol keys commit data:"
puts "Commit count: #{symbol_data[:commits] ? symbol_data[:commits].size : 'nil'}"
if symbol_data[:commits] && symbol_data[:commits].first
  commit = symbol_data[:commits].first
  puts "First commit keys: #{commit.keys.inspect}"
  puts "Timestamp: #{commit[:timestamp]}"
end

symbol_event = Domain::Event.new(
  id: "#{db_event.id}_symbol",
  name: "github.push",
  source: "github",
  data: symbol_data,
  timestamp: db_event.created_at
)

# Create classifier with debug monkeypatching
puts "\n🧩 PREPARING DEBUG CLASSIFIER:"
puts "-" * 80

classifier = Domain::Classifiers::GithubEventClassifier.new(
  Domain::Extractors::DimensionExtractor.new
)

# Debug the classify_push_event method
original_classify_push = classifier.method(:classify_push_event)
debug_classify_push = lambda do |event|
  puts "DEBUG: classify_push_event called with event: #{event.id}"
  puts "DEBUG: Event data keys: #{event.data.keys.inspect}"

  # Check commits
  if event.data.key?(:commits)
    commits = event.data[:commits]
    puts "DEBUG: Found commits array with symbol key, size: #{commits&.size || 'nil'}"
  elsif event.data.key?("commits")
    commits = event.data["commits"]
    puts "DEBUG: Found commits array with string key, size: #{commits&.size || 'nil'}"
  else
    puts "DEBUG: No commits key found in event data"
  end

  # Call original method
  result = original_classify_push.call(event)
  puts "DEBUG: classify_push_event returned #{result[:metrics].size} metrics"

  result
end

# Apply the monkey patch
classifier.define_singleton_method(:classify_push_event, debug_classify_push)

# Also monkey patch the process_commits method
original_process_commits = classifier.method(:process_commits)
debug_process_commits = lambda do |commits, metrics, dimensions, event|
  puts "DEBUG: process_commits called with #{commits.size} commits"
  puts "DEBUG: First commit keys: #{commits.first.keys.inspect}" if commits.first.present?

  # Call the original method
  result = original_process_commits.call(commits, metrics, dimensions, event)

  puts "DEBUG: After process_commits, metrics now has #{metrics.size} metrics"

  # Check for commit volume metrics
  commit_volume_metrics = metrics.select { |m| m[:name] == "github.commit_volume.daily" }
  puts "DEBUG: Found #{commit_volume_metrics.size} github.commit_volume.daily metrics"

  result
end

# Apply the monkey patch
classifier.define_singleton_method(:process_commits, debug_process_commits)

# Test the classifier with string keys
puts "\n🔬 TESTING WITH STRING KEYS:"
puts "-" * 80
string_result = classifier.classify(string_event)
puts "Generated #{string_result[:metrics].size} total metrics with string keys"

daily_metrics = string_result[:metrics].select { |m| m[:name] == "github.commit_volume.daily" }
if daily_metrics.any?
  puts "Found #{daily_metrics.size} github.commit_volume.daily metrics with string keys"
  daily_metrics.each do |metric|
    puts "  Date: #{metric[:dimensions][:date]}, Value: #{metric[:value]}"
  end
else
  puts "No github.commit_volume.daily metrics found with string keys"
end

# Test the classifier with symbol keys
puts "\n🔬 TESTING WITH SYMBOL KEYS:"
puts "-" * 80
symbol_result = classifier.classify(symbol_event)
puts "Generated #{symbol_result[:metrics].size} total metrics with symbol keys"

daily_metrics = symbol_result[:metrics].select { |m| m[:name] == "github.commit_volume.daily" }
if daily_metrics.any?
  puts "Found #{daily_metrics.size} github.commit_volume.daily metrics with symbol keys"
  daily_metrics.each do |metric|
    puts "  Date: #{metric[:dimensions][:date]}, Value: #{metric[:value]}"
  end
else
  puts "No github.commit_volume.daily metrics found with symbol keys"
end
