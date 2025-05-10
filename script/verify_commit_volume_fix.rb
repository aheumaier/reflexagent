#!/usr/bin/env ruby
# frozen_string_literal: true

# This script verifies that the GitHub event classifier can handle commits with both string and symbol keys
# Run with: rails runner script/verify_commit_volume_fix.rb

puts "🔍 Verifying GitHub Event Classifier fix for commit keys..."
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

# Create a test event with string keys (original)
string_key_event = Domain::Event.new(
  id: "#{db_event.id}_string",
  name: "github.push",
  source: "github",
  data: db_event.payload, # Keep original string keys
  timestamp: db_event.created_at
)

puts "📊 TEST 1: EVENT WITH STRING KEYS"
puts "-" * 80
puts "Using event with commits that have string keys"
puts "Commit count: #{string_key_event.data['commits'].size}"
puts "First commit timestamp: #{string_key_event.data['commits'].first['timestamp']}"

# Initialize classifier
classifier = Domain::Classifiers::GithubEventClassifier.new(
  Domain::Extractors::DimensionExtractor.new
)

# Test with string keys
puts "\nRunning classifier with string keys..."
string_result = classifier.classify(string_key_event)
string_daily = string_result[:metrics].select { |m| m[:name] == "github.commit_volume.daily" }

puts "Found #{string_daily.size} github.commit_volume.daily metrics with string keys"
string_daily.each do |metric|
  puts "  Date: #{metric[:dimensions][:date]}, Value: #{metric[:value]}"
end

# Convert payload to symbolized keys for second test
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
end

# Create a test event with symbol keys
symbol_key_event = Domain::Event.new(
  id: "#{db_event.id}_symbol",
  name: "github.push",
  source: "github",
  data: data, # Use symbol keys
  timestamp: db_event.created_at
)

puts "\n📊 TEST 2: EVENT WITH SYMBOL KEYS"
puts "-" * 80
puts "Using event with commits that have symbol keys"
puts "Commit count: #{symbol_key_event.data[:commits].size}"
puts "First commit timestamp: #{symbol_key_event.data[:commits].first[:timestamp]}"

# Test with symbol keys
puts "\nRunning classifier with symbol keys..."
symbol_result = classifier.classify(symbol_key_event)
symbol_daily = symbol_result[:metrics].select { |m| m[:name] == "github.commit_volume.daily" }

puts "Found #{symbol_daily.size} github.commit_volume.daily metrics with symbol keys"
symbol_daily.each do |metric|
  puts "  Date: #{metric[:dimensions][:date]}, Value: #{metric[:value]}"
end

# Summary
puts "\n📋 SUMMARY"
puts "-" * 80
puts "String keys test: #{string_daily.size > 0 ? '✅ PASS' : '❌ FAIL'}"
puts "Symbol keys test: #{symbol_daily.size > 0 ? '✅ PASS' : '❌ FAIL'}"

if string_daily.size == 0
  puts "\n❌ The fix for handling string keys is not working yet"
else
  puts "\n✅ The fix is working correctly for both string and symbol keys!"
end
