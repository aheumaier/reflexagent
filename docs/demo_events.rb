#!/usr/bin/env ruby
# frozen_string_literal: true

# This script demonstrates sending webhook payloads to the ReflexAgent
# Run with: ruby lib/demo_events.rb

require "net/http"
require "uri"
require "json"
require "securerandom"
require "time"

# Configuration
WEBHOOK_HOST = ENV["WEBHOOK_HOST"] || "localhost"
WEBHOOK_PORT = ENV["WEBHOOK_PORT"] || "3000"
WEBHOOK_TOKEN = ENV["WEBHOOK_TOKEN"] || "Test1234"

# Base API URL
BASE_URL = "http://#{WEBHOOK_HOST}:#{WEBHOOK_PORT}/api/v1"

# Helper methods
def send_webhook(source, payload, auth_type = "token")
  uri = URI("#{BASE_URL}/events?source=#{source}")
  http = Net::HTTP.new(uri.host, uri.port)

  request = Net::HTTP::Post.new(uri)
  request["Content-Type"] = "application/json"

  # Handle authentication based on type
  case auth_type
  when "bearer"
    request["Authorization"] = "Bearer #{WEBHOOK_TOKEN}"
  else
    request["X-Webhook-Token"] = WEBHOOK_TOKEN
  end

  # Set the payload
  request.body = payload.to_json

  # Send the request and return the response
  response = http.request(request)

  puts "Response for #{source} webhook: #{response.code} #{response.message}"
  puts "Body: #{response.body}\n\n"

  response
end

# Generate a random ID with a timestamp to ensure uniqueness
def generate_unique_id(prefix = "")
  timestamp = Time.now.to_i
  random = SecureRandom.hex(4)
  "#{prefix}#{timestamp}-#{random}"
end

# Generate a mock GitHub commit payload
def github_commit_payload
  timestamp = Time.now.utc
  random_suffix = SecureRandom.hex(4)

  {
    ref: "refs/heads/main",
    before: SecureRandom.hex(20),
    after: SecureRandom.hex(20),
    repository: {
      id: rand(100_000..999_999),
      name: "ReflexAgent",
      full_name: "acme/ReflexAgent",
      owner: {
        name: "acme",
        email: "developers@acme.com"
      }
    },
    pusher: {
      name: "developer-#{random_suffix}",
      email: "developer-#{SecureRandom.hex(4)}@acme.com"
    },
    commits: [
      {
        id: SecureRandom.hex(20),
        message: "Update dependencies ##{SecureRandom.hex(4)}",
        timestamp: (timestamp - 17).strftime("%Y-%m-%dT%H:%M:%SZ"),
        author: {
          name: "Developer #{SecureRandom.hex(4)}",
          email: "dev-#{SecureRandom.hex(4)}@acme.com"
        }
      },
      {
        id: SecureRandom.hex(20),
        message: "Fix bug in webhook processing ##{SecureRandom.hex(4)}",
        timestamp: timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"),
        author: {
          name: "Developer #{SecureRandom.hex(4)}",
          email: "dev-#{SecureRandom.hex(4)}@acme.com"
        }
      }
    ]
  }
end

# Generate a mock Jira issue updated payload
def jira_issue_payload
  random_suffix = SecureRandom.hex(4)
  current_time = Time.now

  {
    webhookEvent: "jira:issue_updated",
    issue_event_type_name: "issue_updated",
    timestamp: (current_time.to_f * 1000).to_i,
    user: {
      self: "https://jira.acme.com/rest/api/2/user?accountId=#{SecureRandom.hex(8)}",
      name: "user-#{random_suffix}",
      displayName: "User #{SecureRandom.hex(4)}",
      emailAddress: "user-#{SecureRandom.hex(4)}@acme.com"
    },
    issue: {
      id: rand(10_000..99_999).to_s,
      key: "PROJECT-#{rand(100..999)}",
      fields: {
        summary: "Fix the webhook processing bug ##{SecureRandom.hex(3)}",
        status: {
          name: ["In Progress", "In Review", "Done"].sample,
          id: ["10002", "10003", "10004"].sample
        },
        assignee: {
          displayName: "Assignee #{SecureRandom.hex(4)}",
          emailAddress: "assignee-#{SecureRandom.hex(4)}@acme.com"
        }
      }
    }
  }
end

# Generate a mock GitLab merge request payload
def gitlab_merge_request_payload
  timestamp = Time.now.utc
  random_suffix = SecureRandom.hex(4)
  created_time = timestamp - rand(300..1800)

  {
    object_kind: "merge_request",
    event_type: "merge_request",
    user: {
      name: "User #{SecureRandom.hex(4)}",
      username: "user_#{SecureRandom.hex(4)}",
      email: "gitlab-user-#{SecureRandom.hex(4)}@acme.com"
    },
    project: {
      id: rand(10_000..99_999),
      name: "ReflexAgent",
      description: "Track engineering metrics",
      web_url: "https://gitlab.acme.com/acme/reflexagent",
      path_with_namespace: "acme/reflexagent"
    },
    object_attributes: {
      id: rand(10_000..99_999),
      target_branch: "main",
      source_branch: ["feature", "bugfix", "improvement"].sample + "/api-#{SecureRandom.hex(4)}",
      title: ["Update documentation", "Fix UI bugs", "Improve performance"].sample + " ##{SecureRandom.hex(3)}",
      description: ["This MR fixes UI in webhook processing", "This MR improves error handling",
                    "This MR updates dependencies"].sample,
      state: ["opened", "merged", "closed"].sample,
      created_at: created_time.strftime("%Y-%m-%dT%H:%M:%SZ"),
      updated_at: timestamp.strftime("%Y-%m-%dT%H:%M:%SZ")
    }
  }
end

# Define a custom event type
def custom_event_payload
  timestamp = Time.now.utc
  random_id = SecureRandom.uuid

  {
    event_type: "deployment",
    timestamp: timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"),
    environment: ["production", "staging", "development"].sample,
    service: ["web-app", "api-service", "data-processor"].sample,
    status: ["success", "failure", "in_progress"].sample,
    duration: rand(60..600),
    details: {
      version: "v#{rand(1..5)}.#{rand(0..9)}.#{rand(10..99)}",
      deployer: ["CI/CD Pipeline", "Manual Deploy", "Hotfix Deploy"].sample,
      changes: rand(1..30),
      rollback: [true, false].sample,
      instance_id: SecureRandom.hex(8),
      deploy_id: SecureRandom.uuid
    }
  }
end

# Only run the script when it's called directly, not when required/loaded
if __FILE__ == $PROGRAM_NAME
  # Print intro
  puts "ReflexAgent Webhook Demo"
  puts "======================="
  puts "Sending webhooks to #{BASE_URL}/events\n\n"

  # Send GitHub webhook with token auth
  puts "Sending GitHub commit webhook..."
  send_webhook("github", github_commit_payload, "token")

  # Send Jira webhook with bearer auth
  puts "Sending Jira issue webhook..."
  send_webhook("jira", jira_issue_payload, "bearer")

  # Send GitLab webhook with token auth
  puts "Sending GitLab merge request webhook..."
  send_webhook("gitlab", gitlab_merge_request_payload, "token")

  # Send custom webhook with token auth
  puts "Sending custom deployment webhook..."
  send_webhook("deployment", custom_event_payload, "token")

  puts "All done! Check your application logs for details on processing."
end
