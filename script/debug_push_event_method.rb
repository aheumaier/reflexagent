#!/usr/bin/env ruby
# frozen_string_literal: true

# This script analyzes the classify_push_event method to see why process_commits isn't called for string keys
# Run with: rails runner script/debug_push_event_method.rb

puts "🔍 Debugging classify_push_event method..."
puts "=" * 80

# Get the source code of the method
classifier = Domain::Classifiers::GithubEventClassifier.new(
  Domain::Extractors::DimensionExtractor.new
)

puts "📋 CLASSIFY_PUSH_EVENT SOURCE:"
puts "-" * 80

# Get method source
method_source = File.read("app/core/domain/classifiers/github_event_classifier.rb")
push_method_start = method_source.index("def classify_push_event")
push_method_end = method_source.index("end", push_method_start)
push_method_end = method_source.index("end", push_method_end + 3) # Find the second end

# Extract and show relevant part
push_method_code = method_source[push_method_start...push_method_end]
puts push_method_code.split("\n").map.with_index { |line, i| "#{i + 1}: #{line}" }.join("\n")

# Look at the conditions for calling process_commits
puts "\n🔍 CHECKING COMMITS PROCESSING CONDITION:"
puts "-" * 80

db_event = DomainEvent.where(event_type: "github.push.created").order(created_at: :desc).first
if db_event.nil?
  puts "❌ No GitHub push events found!"
  exit
end

# Extract string and symbol versions of data
string_data = db_event.payload
symbol_data = {}
string_data.each { |k, v| symbol_data[k.to_sym] = v }

# Setup for testing conditions
puts "Testing conditions for both string and symbol keys:"

# Check the condition for string keys
string_commits_present = string_data["commits"].present?
puts "String keys: string_data['commits'].present? => #{string_commits_present}"

# Check the condition for symbol keys
symbol_commits_present = symbol_data[:commits].present?
puts "Symbol keys: symbol_data[:commits].present? => #{symbol_commits_present}"

# Check the actual code in the method
puts "\n🔧 ANALYZING METHOD LOGIC:"
puts "-" * 80

# Get the specific if statement that checks for commits
commit_check_line = push_method_code.split("\n").detect { |line| line.match?(/if push_data\[:commits\]/) }
puts "Commits check condition: #{commit_check_line.strip}"

# Create a test case that matches the method implementation
puts "\n🧪 TESTING PUSH_DATA ACCESS:"
puts "-" * 80

# Create events with both key types
string_event = Domain::Event.new(
  id: "string_test",
  name: "github.push",
  source: "github",
  data: string_data,
  timestamp: Time.now
)

symbol_event = Domain::Event.new(
  id: "symbol_test",
  name: "github.push",
  source: "github",
  data: symbol_data,
  timestamp: Time.now
)

# Test the dimension extraction
puts "Using the actual method for testing:"

# Define a patch method to see how push_data is extracted
test_push_logic = lambda do |event|
  # Same logic as in the classify_push_event method
  puts "Event data keys: #{event.data.keys.inspect}"
  dimensions = { repository: "unknown", source: event.source }
  push_data = event.data || {}

  # Check how commits are accessed in the original code
  has_symbol_commits = push_data[:commits].present?
  has_string_commits = begin
    push_data["commits"].present?
  rescue StandardError
    false
  end

  puts "push_data[:commits].present? => #{has_symbol_commits}"
  puts "push_data['commits'].present? => #{has_string_commits}"

  # Test the extract_from_data method
  commits = extract_from_data(push_data, :commits)
  puts "extract_from_data result: #{commits.present? ? 'Found' : 'Not found'}"
  puts "Commits class: #{commits.class.name}" if commits
  puts "Commits size: #{commits.size}" if commits.respond_to?(:size)
end

# Mock extract_from_data method
def extract_from_data(data, *keys)
  stringified_keys = keys.map(&:to_s)
  symbolized_keys = keys.map(&:to_sym)

  # Try symbol path first
  value = data.dig(*symbolized_keys)

  # Fall back to string path if needed
  if value.nil?
    value = begin
      data.dig(*stringified_keys)
    rescue StandardError
      nil
    end
  end

  value
end

puts "\nTesting with string keys:"
test_push_logic.call(string_event)

puts "\nTesting with symbol keys:"
test_push_logic.call(symbol_event)

# Print the fix
puts "\n🛠 SOLUTION:"
puts "-" * 80
puts "The issue is in classify_push_event method where it checks for :commits using symbol key only."
puts "Should replace:"
puts "  if push_data[:commits].present?"
puts "With:"
puts "  commits = extract_from_data(push_data, :commits)"
puts "  if commits.present?"
