#!/usr/bin/env ruby
# frozen_string_literal: true

# This script tests the extract_from_data method in the GitHub event classifier
# Run with: rails runner script/debug_extract_from_data.rb

puts "🔍 Testing extract_from_data method with string and symbol keys..."
puts "=" * 80

# Get a GitHub push event
db_event = DomainEvent.where(event_type: "github.push.created").order(created_at: :desc).first

if db_event.nil?
  puts "❌ No GitHub push events found!"
  exit
end

puts "📊 ANALYZING EVENT:"
puts "-" * 80
puts "Event ID: #{db_event.id}"
puts "Commits count: #{db_event.payload['commits'].size}"

# Get the first commit from the payload
first_commit = db_event.payload["commits"].first
puts "First commit timestamp (string key): #{first_commit['timestamp']}" if first_commit
puts "First commit object_id: #{first_commit.object_id}" if first_commit

# Initialize the classifier
classifier = Domain::Classifiers::GithubEventClassifier.new(
  Domain::Extractors::DimensionExtractor.new
)

# Create a mock for the extract_from_data method that we can call directly
mock_extract_from_data = lambda do |data, *keys|
  stringified_keys = keys.map(&:to_s)
  symbolized_keys = keys.map(&:to_sym)

  # Try symbol path first
  value = data.dig(*symbolized_keys)
  puts "  Symbol keys lookup: #{symbolized_keys.inspect}, result: #{value.inspect}"

  # Fall back to string path if needed
  if value.nil?
    value = data.dig(*stringified_keys)
    puts "  String keys lookup: #{stringified_keys.inspect}, result: #{value.inspect}"
  end

  value
end

# Get the real extract_from_data method
actual_extract_from_data = classifier.method(:extract_from_data)

puts "\n📝 TESTING HASH ACCESS:"
puts "-" * 80

# Try accessing with both string and symbol keys
test_cases = [
  # Original commit from event
  { name: "Original commit (string keys)", data: first_commit, keys: [:timestamp] },
  # Test data with string keys
  { name: "Test hash (string keys)", data: { "timestamp" => "2025-05-08T12:34:56Z", "id" => "123" },
    keys: [:timestamp] },
  # Test data with symbol keys
  { name: "Test hash (symbol keys)", data: { timestamp: "2025-05-08T12:34:56Z", id: "123" }, keys: [:timestamp] },
  # Nested test
  { name: "Nested hash (string keys)", data: { "author" => { "name" => "Test Author" } }, keys: [:author, :name] },
  # Nested test mixed
  { name: "Nested hash (mixed keys)", data: { "author" => { name: "Test Author" } }, keys: [:author, :name] }
]

test_cases.each do |test_case|
  puts "Test case: #{test_case[:name]}"
  puts "Data: #{test_case[:data].inspect}"

  # Test with our mock implementation
  puts "With mock extract_from_data:"
  result = mock_extract_from_data.call(test_case[:data], *test_case[:keys])
  puts "  Result: #{result.inspect}"

  # Test with the actual implementation
  puts "With actual extract_from_data:"
  begin
    result = actual_extract_from_data.call(test_case[:data], *test_case[:keys])
    puts "  Result: #{result.inspect}"
  rescue StandardError => e
    puts "  Error: #{e.message}"
  end

  puts
end

# Test with direct dig calls
puts "\n📝 TESTING DIRECT DIG CALLS:"
puts "-" * 80

test_cases.each do |test_case|
  puts "Test case: #{test_case[:name]}"

  # Try symbol keys
  symbol_keys = test_case[:keys].map(&:to_sym)
  begin
    result = test_case[:data].dig(*symbol_keys)
    puts "  dig with symbol keys #{symbol_keys.inspect}: #{result.inspect}"
  rescue StandardError => e
    puts "  Error with symbol keys: #{e.message}"
  end

  # Try string keys
  string_keys = test_case[:keys].map(&:to_s)
  begin
    result = test_case[:data].dig(*string_keys)
    puts "  dig with string keys #{string_keys.inspect}: #{result.inspect}"
  rescue StandardError => e
    puts "  Error with string keys: #{e.message}"
  end

  puts
end
