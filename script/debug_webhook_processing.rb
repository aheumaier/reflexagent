#!/usr/bin/env ruby
# frozen_string_literal: true

# This script debugs the GitHub webhook processing for deployment status events
# Run with: rails runner script/debug_webhook_processing.rb

require "json"
require "securerandom"

puts "🔍 Debugging GitHub Deployment Status Event Processing"
puts "======================================================"

# Create instances of the key components
puts "\n1️⃣ Setting up testing components..."
web_adapter = Web::WebAdapter.new
github_classifier = Domain::Classifiers::GithubEventClassifier.new
metric_classifier = DependencyContainer.resolve(:metric_classifier)
dimension_extractor = Domain::Extractors::DimensionExtractor.new

# Sample repository and environment info
repository_name = "test-service"
repo_owner = "acme"
repository_full_name = "#{repo_owner}/#{repository_name}"
environment = "production"
deployment_id = rand(1_000_000..9_999_999)

puts "\n2️⃣ Creating test deployment status payload..."
# Sample deployment status payload similar to what comes from GitHub
deployment_created_at = Time.now - 600 # 10 minutes ago
deployment_status_completed_at = Time.now - 60 # 1 minute ago

deployment_status_payload = {
  action: "created",
  deployment_status: {
    url: "https://api.github.com/repos/#{repository_full_name}/deployments/#{deployment_id}/statuses/#{rand(1..1000)}",
    id: rand(1_000_000..9_999_999),
    state: "success",
    creator: {
      login: "alice",
      id: rand(1000..9999)
    },
    description: "Deployment succeeded",
    environment: environment,
    created_at: deployment_created_at.iso8601,
    updated_at: deployment_status_completed_at.iso8601,
    deployment_id: deployment_id,
    deployment_url: "https://api.github.com/repos/#{repository_full_name}/deployments/#{deployment_id}"
  },
  deployment: {
    url: "https://api.github.com/repos/#{repository_full_name}/deployments/#{deployment_id}",
    id: deployment_id,
    task: "deploy",
    environment: environment,
    description: "Deploy to #{environment}",
    created_at: deployment_created_at.iso8601,
    creator: {
      login: "alice",
      id: rand(1000..9999)
    },
    sha: SecureRandom.hex(20),
    ref: "main"
  },
  repository: {
    id: rand(100_000..999_999),
    name: repository_name,
    full_name: repository_full_name,
    owner: {
      login: repo_owner,
      id: rand(1000..9999)
    }
  },
  sender: {
    login: "alice",
    id: rand(1000..9999)
  }
}

puts "\n3️⃣ Testing determine_github_event_type method..."
# First, let's test how the event type is determined by the WebAdapter
Thread.current[:http_headers] = { "X-GitHub-Event" => "deployment_status" }
puts "Setting X-GitHub-Event header to: deployment_status"

# Directly test the determine_github_event_type method
event_type = web_adapter.send(:determine_github_event_type, deployment_status_payload)
puts "Determined event type: #{event_type}"

puts "\n4️⃣ Testing WebAdapter receive_event method..."
# Test the complete event creation flow
raw_payload = deployment_status_payload.to_json
event = web_adapter.receive_event(raw_payload, source: "github")
puts "Created event with name: #{event.name}"

puts "\n5️⃣ Testing event classification directly with GithubEventClassifier..."
# Test the classifier with both formats of event name
puts "\nA) Testing with original event name: #{event.name}"
result1 = github_classifier.classify(event)
puts "Classification returned #{result1[:metrics].size} metrics:"
result1[:metrics].each do |metric|
  puts "  • #{metric[:name]}: #{metric[:value]} (#{metric[:dimensions].slice(:environment, :state).inspect})"
end

puts "\nB) Testing with manually formatted event name: github.deployment_status"
event2 = Domain::Event.new(
  name: "github.deployment_status",
  source: "github",
  data: deployment_status_payload,
  timestamp: Time.now
)
result2 = github_classifier.classify(event2)
puts "Classification returned #{result2[:metrics].size} metrics:"
result2[:metrics].each do |metric|
  puts "  • #{metric[:name]}: #{metric[:value]} (#{metric[:dimensions].slice(:environment, :state).inspect})"
end

puts "\n6️⃣ Testing the complete flow via MetricClassifier..."
result3 = metric_classifier.classify_event(event)
puts "Classification returned #{result3[:metrics].size} metrics:"
result3[:metrics].each do |metric|
  puts "  • #{metric[:name]}: #{metric[:value]} (#{metric[:dimensions].slice(:environment, :state).inspect})"
end

puts "\n7️⃣ Manual database check..."
begin
  puts "\nExisting deployment_status metrics in DB:"
  metrics = DomainMetric.where("name LIKE ?", "github.deployment_status%").count
  puts "Found #{metrics} deployment_status metrics"
rescue StandardError => e
  puts "Error checking database: #{e.message}"
end

puts "\n✅ Debug complete"
