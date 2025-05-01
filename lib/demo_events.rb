#!/usr/bin/env ruby
# frozen_string_literal: true

# This script demonstrates sending webhook payloads to the ReflexAgent
# Run with: ruby lib/demo_events.rb

require "net/http"
require "uri"
require "json"
require "securerandom"

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

# Generate a mock GitHub commit payload
def github_commit_payload
  {
    ref: "refs/heads/main",
    before: SecureRandom.hex(20),
    after: SecureRandom.hex(20),
    repository: {
      id: 123_456,
      name: "ReflexAgent",
      full_name: "acme/ReflexAgent",
      owner: {
        name: "acme",
        email: "developers@acme.com"
      }
    },
    pusher: {
      name: "developer",
      email: "developer@acme.com"
    },
    commits: [
      {
        id: SecureRandom.hex(20),
        message: "Fix bug in webhook processing",
        timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
        author: {
          name: "Developer Name",
          email: "developer@acme.com"
        }
      },
      {
        id: SecureRandom.hex(20),
        message: "Update documentation",
        timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
        author: {
          name: "Another Developer",
          email: "another@acme.com"
        }
      }
    ]
  }
end

# Generate a mock Jira issue updated payload
def jira_issue_payload
  {
    webhookEvent: "jira:issue_updated",
    issue_event_type_name: "issue_updated",
    timestamp: (Time.now.to_f * 1000).to_i,
    user: {
      self: "https://jira.acme.com/rest/api/2/user?accountId=123456",
      name: "user",
      displayName: "Jane Doe",
      emailAddress: "jane@acme.com"
    },
    issue: {
      id: "123456",
      key: "PROJECT-123",
      fields: {
        summary: "Fix the webhook processing bug",
        status: {
          name: "Done",
          id: "10002"
        },
        assignee: {
          displayName: "Jane Doe",
          emailAddress: "jane@acme.com"
        }
      }
    }
  }
end

# Generate a mock GitLab merge request payload
def gitlab_merge_request_payload
  {
    object_kind: "merge_request",
    event_type: "merge_request",
    user: {
      name: "John Smith",
      username: "jsmith",
      email: "john@acme.com"
    },
    project: {
      id: 12_345,
      name: "ReflexAgent",
      description: "Track engineering metrics",
      web_url: "https://gitlab.acme.com/acme/reflexagent",
      path_with_namespace: "acme/reflexagent"
    },
    object_attributes: {
      id: 6789,
      target_branch: "main",
      source_branch: "feature/webhook-updates",
      title: "Update webhook processing",
      description: "This MR improves error handling in webhook processing",
      state: "opened",
      created_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
      updated_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }
  }
end

# Define a custom event type
def custom_event_payload
  {
    event_type: "deployment",
    timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    environment: "production",
    service: "web-app",
    status: "success",
    duration: 120,
    details: {
      version: "v1.2.3",
      deployer: "CI/CD Pipeline",
      changes: 12,
      rollback: false
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
