#!/usr/bin/env ruby
# frozen_string_literal: true

# This script sends test deployment and deployment status events to verify lead time metrics
# Run with: rails runner script/send_deployment_events.rb

require "net/http"
require "uri"
require "json"
require "securerandom"
require "time"
require "openssl"

# Configuration
WEBHOOK_HOST = ENV["WEBHOOK_HOST"] || "localhost"
WEBHOOK_PORT = ENV["WEBHOOK_PORT"] || "3000"
WEBHOOK_TOKEN = ENV["WEBHOOK_TOKEN"] || "Test1234"
WEBHOOK_URL = "http://#{WEBHOOK_HOST}:#{WEBHOOK_PORT}/api/v1/events"

puts "===== Test Deployment Events for Lead Time Metrics ====="

# Helper method to send a webhook
def send_webhook(github_event, payload)
  uri = URI("#{WEBHOOK_URL}?source=github")
  http = Net::HTTP.new(uri.host, uri.port)

  request = Net::HTTP::Post.new(uri)
  request["Content-Type"] = "application/json"
  request["X-Webhook-Token"] = WEBHOOK_TOKEN

  # GitHub identifies event type in the X-GitHub-Event header
  request["X-GitHub-Event"] = github_event
  request["X-GitHub-Delivery"] = SecureRandom.uuid

  # Add a signature header to pass webhook validation
  payload_json = payload.to_json
  signature = "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), WEBHOOK_TOKEN, payload_json)
  request["X-Hub-Signature-256"] = signature

  # Set the payload directly
  request.body = payload_json

  # Send the request and return the response
  response = http.request(request)

  puts "Response for GitHub webhook '#{github_event}': #{response.code} #{response.message}"
  puts "Body: #{response.body}"

  response
end

# Generate repository and environment information
repository_name = "test-service"
repo_owner = "acme"
repository_full_name = "#{repo_owner}/#{repository_name}"
environment = "production"

# Generate a unique deployment ID
deployment_id = rand(1_000_000..9_999_999)

# 1. Create a deployment event
puts "\n⚙️ Step 1: Creating deployment event..."
deployment_created_at = Time.now - 600 # 10 minutes ago
deployment_payload = {
  action: "created",
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

deploy_response = send_webhook("deployment", deployment_payload)

# 2. Create a deployment status event (success)
puts "\n⚙️ Step 2: Creating deployment status event (success)..."
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

status_response = send_webhook("deployment_status", deployment_status_payload)

# Process the metrics - let's wait a moment to ensure events are processed
puts "\n⚙️ Step 3: Waiting for events to be processed..."
puts "Waiting 5 seconds for events to be processed..."
sleep(5)

puts "\n⚙️ Step 4: Running MetricAggregationJob..."
result = MetricAggregationJob.new.perform("daily")
puts "MetricAggregationJob completed"

puts "\n===== Event sending complete ====="
puts "Deployment created at: #{deployment_created_at.iso8601}"
puts "Deployment completed at: #{deployment_status_completed_at.iso8601}"
puts "Lead time: #{(deployment_status_completed_at - deployment_created_at).to_i} seconds (#{((deployment_status_completed_at - deployment_created_at) / 60.0).round(2)} minutes)"
puts "Run 'rails runner script/check_deployment_events.rb' to verify metrics were created"
