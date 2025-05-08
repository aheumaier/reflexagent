#!/usr/bin/env ruby
# frozen_string_literal: true

# This script debugs the deployment status event classification
# Run with: rails runner script/debug_deployment_status.rb

require "json"

puts "🧪 Debugging GitHub deployment status event classification"
puts "======================================================"

# Create a GitHub classifier
github_classifier = Domain::Classifiers::GithubEventClassifier.new

# Sample payload based on actual log data
payload = {
  action: "created",
  deployment_status: {
    url: "https://api.github.com/repos/acme/auth-service/deployments/7871644/statuses/405",
    id: 1_190_160,
    state: "success",
    creator: {
      login: "charlie",
      id: 2253
    },
    description: "Deployment succeeded",
    environment: "staging",
    created_at: "2025-05-04T03:17:50Z",
    updated_at: "2025-05-04T03:17:50Z",
    deployment_id: 7_871_644,
    deployment_url: "https://api.github.com/repos/acme/auth-service/deployments/7871644"
  },
  deployment: {
    url: "https://api.github.com/repos/acme/auth-service/deployments/7871644",
    id: 7_871_644,
    task: "deploy",
    environment: "staging",
    description: "Deploy to staging",
    created_at: "2025-05-04T03:12:50Z",
    creator: {
      login: "grace",
      id: 2776
    },
    sha: "302e81748f5219c0493dbe6a8bd61c85d3e1a999",
    ref: "main"
  },
  repository: {
    id: 702_691,
    name: "auth-service",
    full_name: "acme/auth-service",
    owner: {
      login: "acme",
      id: 8923
    }
  },
  sender: {
    login: "bob",
    id: 7491
  }
}

# Test case 1: Event name without action
puts "\n➡️ Test case 1: Event name without action ('github.deployment_status')"

event1 = Domain::Event.new(
  name: "github.deployment_status",
  source: "github",
  data: payload,
  timestamp: Time.now
)

begin
  result1 = github_classifier.classify(event1)
  puts "🟢 Classification successful"
  puts "Classification returned #{result1[:metrics].size} metrics:"
  result1[:metrics].each do |metric|
    puts "  • #{metric[:name]}: #{metric[:value]} (#{metric[:dimensions].slice(:environment, :state).inspect})"
  end
rescue StandardError => e
  puts "🔴 Classification failed: #{e.message}"
  puts e.backtrace.first(5)
end

# Test case 2: Event name with action
puts "\n➡️ Test case 2: Event name with action ('github.deployment_status.created')"

event2 = Domain::Event.new(
  name: "github.deployment_status.created",
  source: "github",
  data: payload,
  timestamp: Time.now
)

begin
  result2 = github_classifier.classify(event2)
  puts "🟢 Classification successful"
  puts "Classification returned #{result2[:metrics].size} metrics:"
  result2[:metrics].each do |metric|
    puts "  • #{metric[:name]}: #{metric[:value]} (#{metric[:dimensions].slice(:environment, :state).inspect})"
  end
rescue StandardError => e
  puts "🔴 Classification failed: #{e.message}"
  puts e.backtrace.first(5)
end

# Test case 3: Print method call details
puts "\n➡️ Test case 3: Debug classifier method call path"

# Temporarily modify the classifier to track method calls
puts "Adding debug hooks to classifier methods..."

# Add debug hooks for relevant methods
original_classify = github_classifier.method(:classify)
github_classifier.define_singleton_method(:classify) do |event|
  puts "DEBUG: classify called with event name: #{event.name}"
  original_classify.call(event)
end

original_classify_deployment_status = github_classifier.method(:classify_deployment_status_event)
github_classifier.define_singleton_method(:classify_deployment_status_event) do |event, action|
  puts "DEBUG: classify_deployment_status_event called with action: #{action}"
  original_classify_deployment_status.call(event, action)
end

# Test with both formats
puts "\nTesting with 'github.deployment_status':"
github_classifier.classify(event1)

puts "\nTesting with 'github.deployment_status.created':"
github_classifier.classify(event2)

puts "\n✅ Debug complete"
