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
BATCH_SIZE = (ENV["BATCH_SIZE"] || "25").to_i
EVENTS_COUNT = (ENV["EVENTS_COUNT"] || "200").to_i
SEND_DELAY = (ENV["SEND_DELAY"] || "0.1").to_f # seconds between batches
DAYS_TO_SIMULATE = (ENV["DAYS_TO_SIMULATE"] || "14").to_i
TEAM_SIZE = 8 # Number of team members

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

  # For GitHub events, add the X-GitHub-Event header based on the event name
  if source == "github" && payload[:name].present?
    # Split the name (e.g., "deployment_status.created" -> "deployment_status")
    event_type = payload[:name].to_s.split('.').first
    if event_type.present?
      puts "Adding X-GitHub-Event header: #{event_type}"
      request["X-GitHub-Event"] = event_type
      request["X-GitHub-Delivery"] = SecureRandom.uuid
    end
  end

  # Set the payload
  request.body = payload.to_json

  # Send the request and return the response
  response = http.request(request)

  puts "Response for #{source} webhook: #{response.code} #{response.message}"
  puts "Body: #{response.body}\n\n"

  response
end

# Send a batch of webhooks
def send_webhook_batch(events_batch)
  threads = []
  events_batch.each do |event|
    threads << Thread.new do
      # Debug info for GitHub events
      if event[:source] == "github"
        puts "Sending GitHub event: #{event[:name]} - Has deployment_status: #{event[:payload].key?(:deployment_status)}"
      end
      send_webhook(event[:source], event[:payload].merge(name: event[:name]))
    end
  end
  threads.each(&:join)
end

# Generate a random ID with a timestamp to ensure uniqueness
def generate_unique_id(prefix = "")
  timestamp = Time.now.to_i
  random = SecureRandom.hex(4)
  "#{prefix}#{timestamp}-#{random}"
end

# Generate a random timestamp within the specified range
def random_time_in_range(start_time, end_time)
  Time.at(rand(start_time.to_i..end_time.to_i)).utc
end

# ============ GitHub Event Generators =============

# Generate a mock GitHub push payload
def github_push_payload(repository_name, repo_owner, timestamp, branch = "main")
  random_suffix = SecureRandom.hex(4)
  commit_count = rand(1..5)
  commit_time_offset = rand(5..30) * 60 # 5-30 minutes in seconds

  {
    ref: "refs/heads/#{branch}",
    before: SecureRandom.hex(20),
    after: SecureRandom.hex(20),
    repository: {
      id: rand(100_000..999_999),
      name: repository_name,
      full_name: "#{repo_owner}/#{repository_name}",
      owner: {
        name: repo_owner,
        email: "#{repo_owner.downcase}@example.com"
      }
    },
    pusher: {
      name: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
      email: "developer-#{random_suffix}@example.com"
    },
    commits: Array.new(commit_count) do |i|
      commit_timestamp = timestamp - ((commit_count - i) * commit_time_offset)
      {
        id: SecureRandom.hex(20),
        message: ["Fix bug in #{branch} branch", "Update dependencies", "Add tests", "Refactor code",
                  "Improve performance"].sample,
        timestamp: commit_timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"),
        author: {
          name: ["Alice Smith", "Bob Johnson", "Charlie Davis", "Dana Lee", "Evan Brown", "Frank Wilson", "Grace Taylor", "Hector Rodriguez"].sample,
          email: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample + "@example.com"
        }
      }
    end
  }
end

# Generate a GitHub pull request payload
def github_pull_request_payload(action, repository_name, repo_owner, timestamp, source_branch, target_branch = "main")
  {
    action: action,
    number: rand(1..1000),
    pull_request: {
      url: "https://api.github.com/repos/#{repo_owner}/#{repository_name}/pulls/#{rand(1..1000)}",
      id: rand(100_000..999_999),
      html_url: "https://github.com/#{repo_owner}/#{repository_name}/pull/#{rand(1..1000)}",
      state: action == "closed" ? "closed" : "open",
      title: ["Add new feature", "Fix bug", "Update documentation", "Refactor code", "Improve performance"].sample,
      user: {
        login: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
        id: rand(1000..9999)
      },
      body: "This PR addresses some important changes",
      created_at: (timestamp - (rand(1..24) * 3600)).strftime("%Y-%m-%dT%H:%M:%SZ"), # hours converted to seconds
      updated_at: timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"),
      closed_at: action == "closed" ? timestamp.strftime("%Y-%m-%dT%H:%M:%SZ") : nil,
      merged_at: action == "merged" ? timestamp.strftime("%Y-%m-%dT%H:%M:%SZ") : nil,
      merge_commit_sha: action == "merged" ? SecureRandom.hex(20) : nil,
      head: {
        ref: source_branch,
        sha: SecureRandom.hex(20)
      },
      base: {
        ref: target_branch,
        sha: SecureRandom.hex(20)
      }
    },
    repository: {
      id: rand(100_000..999_999),
      name: repository_name,
      full_name: "#{repo_owner}/#{repository_name}",
      owner: {
        login: repo_owner,
        id: rand(1000..9999)
      }
    },
    sender: {
      login: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
      id: rand(1000..9999)
    }
  }
end

# Generate a GitHub branch creation payload
def github_create_payload(repository_name, repo_owner, timestamp, ref_type, ref)
  payload = {
    ref: ref,
    ref_type: ref_type,
    master_branch: "main",
    description: "",
    pusher_type: "user",
    repository: {
      id: rand(100_000..999_999),
      name: repository_name,
      full_name: "#{repo_owner}/#{repository_name}",
      owner: {
        login: repo_owner,
        id: rand(1000..9999)
      }
    },
    sender: {
      login: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
      id: rand(1000..9999)
    },
    created_at: timestamp.strftime("%Y-%m-%dT%H:%M:%SZ")
  }

  # Add debug info
  puts "DEBUG: Branch creation payload:"
  puts "DEBUG: Keys present: #{payload.keys.join(', ')}"
  puts "DEBUG: ref_type: #{payload[:ref_type]}, ref: #{payload[:ref]}"

  payload
end

# Generate a GitHub check run payload
def github_check_run_payload(action, status, conclusion, repository_name, repo_owner, timestamp, branch = "main")
  {
    action: action,
    check_run: {
      id: rand(1_000_000..9_999_999),
      head_sha: SecureRandom.hex(20),
      name: ["build", "test", "lint", "security-scan"].sample,
      status: status,
      conclusion: conclusion,
      started_at: (timestamp - (rand(1..10) * 60)).strftime("%Y-%m-%dT%H:%M:%SZ"), # minutes converted to seconds
      completed_at: status == "completed" ? timestamp.strftime("%Y-%m-%dT%H:%M:%SZ") : nil,
      output: {
        title: if status == "completed"
                 conclusion == "success" ? "All tests passed" : "Tests failed"
               else
                 "Running tests"
               end,
        summary: if status == "completed"
                   conclusion == "success" ? "All checks have passed" : "Some checks failed"
                 else
                   "In progress"
                 end
      }
    },
    repository: {
      id: rand(100_000..999_999),
      name: repository_name,
      full_name: "#{repo_owner}/#{repository_name}",
      owner: {
        login: repo_owner,
        id: rand(1000..9999)
      }
    },
    sender: {
      login: ["github-actions[bot]", "alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
      id: rand(1000..9999)
    }
  }
end

# Generate a GitHub workflow run payload
def github_workflow_run_payload(action, status, conclusion, repository_name, repo_owner, timestamp, branch = "main")
  {
    action: action,
    workflow_run: {
      id: rand(1_000_000..9_999_999),
      name: ["CI", "Build and Test", "Deploy", "Release"].sample,
      head_sha: SecureRandom.hex(20),
      run_number: rand(1..1000),
      event: ["push", "pull_request", "workflow_dispatch"].sample,
      status: status,
      conclusion: conclusion,
      workflow_id: rand(1000..9999),
      head_branch: branch,
      run_started_at: (timestamp - (rand(1..10) * 60)).strftime("%Y-%m-%dT%H:%M:%SZ"), # minutes converted to seconds
      run_attempt: 1,
      head_repository: {
        full_name: "#{repo_owner}/#{repository_name}"
      }
    },
    repository: {
      id: rand(100_000..999_999),
      name: repository_name,
      full_name: "#{repo_owner}/#{repository_name}",
      owner: {
        login: repo_owner,
        id: rand(1000..9999)
      }
    },
    sender: {
      login: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
      id: rand(1000..9999)
    }
  }
end

# Generate a GitHub deployment payload
def github_deployment_payload(repository_name, repo_owner, timestamp, environment)
  {
    action: "created",
    deployment: {
      url: "https://api.github.com/repos/#{repo_owner}/#{repository_name}/deployments/#{rand(1..1000)}",
      id: rand(1_000_000..9_999_999),
      task: "deploy",
      environment: environment,
      description: "Deploy to #{environment}",
      created_at: timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"),
      creator: {
        login: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
        id: rand(1000..9999)
      },
      sha: SecureRandom.hex(20),
      ref: "main"
    },
    repository: {
      id: rand(100_000..999_999),
      name: repository_name,
      full_name: "#{repo_owner}/#{repository_name}",
      owner: {
        login: repo_owner,
        id: rand(1000..9999)
      }
    },
    sender: {
      login: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
      id: rand(1000..9999)
    }
  }
end

# Generate a GitHub deployment status payload
def github_deployment_status_payload(repository_name, repo_owner, timestamp, environment, state)
  deployment_id = rand(1_000_000..9_999_999)

  {
    action: "created",
    deployment_status: {
      url: "https://api.github.com/repos/#{repo_owner}/#{repository_name}/deployments/#{deployment_id}/statuses/#{rand(1..1000)}",
      id: rand(1_000_000..9_999_999),
      state: state,
      creator: {
        login: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
        id: rand(1000..9999)
      },
      description: if state == "success"
                     "Deployment succeeded"
                   else
                     (state == "failure" ? "Deployment failed" : "Deployment in progress")
                   end,
      environment: environment,
      created_at: timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"),
      updated_at: timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"),
      deployment_id: deployment_id,
      deployment_url: "https://api.github.com/repos/#{repo_owner}/#{repository_name}/deployments/#{deployment_id}"
    },
    deployment: {
      url: "https://api.github.com/repos/#{repo_owner}/#{repository_name}/deployments/#{deployment_id}",
      id: deployment_id,
      task: "deploy",
      environment: environment,
      description: "Deploy to #{environment}",
      created_at: (timestamp - (rand(1..5) * 60)).strftime("%Y-%m-%dT%H:%M:%SZ"), # minutes converted to seconds
      creator: {
        login: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
        id: rand(1000..9999)
      },
      sha: SecureRandom.hex(20),
      ref: "main"
    },
    repository: {
      id: rand(100_000..999_999),
      name: repository_name,
      full_name: "#{repo_owner}/#{repository_name}",
      owner: {
        login: repo_owner,
        id: rand(1000..9999)
      }
    },
    sender: {
      login: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
      id: rand(1000..9999)
    }
  }
end

# Function to generate CI/CD event
def ci_event_payload(operation, status, repository_name, start_time, end_time)
  duration = end_time.to_i - start_time.to_i

  {
    project: repository_name,
    provider: "github-actions",
    operation: operation,
    status: status,
    start_time: start_time.strftime("%Y-%m-%dT%H:%M:%SZ"),
    end_time: end_time.strftime("%Y-%m-%dT%H:%M:%SZ"),
    duration: duration,
    details: {
      job_id: SecureRandom.uuid,
      workflow: ["CI", "Build and Test", "Deploy"].sample,
      trigger: ["push", "pull_request", "schedule"].sample
    }
  }
end

# Generate engineering workflow events (150 events over 14 days)
def generate_engineering_workflow_events(num_events = 150, days = 14)
  events = []
  repositories = ["api-service", "frontend", "data-processor", "auth-service", "monitoring-tools"]
  repo_owner = "acme"

  # Define time range (14 days ago until now)
  end_time = Time.now.utc
  start_time = end_time - (days * 24 * 60 * 60)

  # Track branches and PRs
  branches = Hash.new { |h, k| h[k] = [] }
  pull_requests = Hash.new { |h, k| h[k] = [] }
  repositories.each do |repo|
    branches[repo] << "main" # Main branch always exists
  end

  # Generate events
  num_events.times do |i|
    # Generate a random timestamp within the range
    timestamp = random_time_in_range(start_time, end_time)
    repository = repositories.sample

    # Determine event type based on realistic workflow probabilities
    event_type = case rand(100)
                 when 0..30 then :push           # 31% - Most common event
                 when 31..40 then :create_branch # 10%
                 when 41..50 then :pr_open       # 10%
                 when 51..58 then :pr_close      # 8%
                 when 59..66 then :pr_merge      # 8%
                 when 67..80 then :check_run     # 14%
                 when 81..89 then :workflow_run  # 9%
                 when 90..94 then :deployment    # 5%
                 when 95..99 then :deploy_status # 5%
                 end

    # Create the appropriate event payload
    case event_type
    when :push
      # Most pushes go to existing branches
      branch = branches[repository].sample || "main"
      payload = github_push_payload(repository, repo_owner, timestamp, branch)
      events << { source: "github", name: "push", payload: payload, timestamp: timestamp }

      # Generate CI event after push (70% chance)
      if rand < 0.7
        ci_start = timestamp + (rand(1..3) * 60) # minutes converted to seconds
        ci_duration = rand(2..10) * 60 # minutes converted to seconds
        ci_end = ci_start + ci_duration
        ci_status = rand < 0.9 ? "completed" : "failed" # 90% success rate

        ci_payload = ci_event_payload("build", ci_status, repository, ci_start, ci_end)
        events << { source: "ci", name: "ci.build.#{ci_status}", payload: ci_payload, timestamp: ci_end }
      end

    when :create_branch
      # Create a new branch
      branch_name = ["feature", "bugfix", "hotfix",
                     "release"].sample + "/" + ["auth", "ui", "api", "perf",
                                                "refactor"].sample + "-" + SecureRandom.hex(3)
      payload = github_create_payload(repository, repo_owner, timestamp, "branch", branch_name)
      branches[repository] << branch_name
      events << { source: "github", name: "create", payload: payload, timestamp: timestamp }

    when :pr_open
      # Can only open PR if we have at least one branch besides main
      if branches[repository].size > 1
        source_branch = (branches[repository] - ["main"]).sample || ("feature/sample-" + SecureRandom.hex(3))
        payload = github_pull_request_payload("opened", repository, repo_owner, timestamp, source_branch)
        pr_id = payload[:number]
        pull_requests[repository] << { id: pr_id, branch: source_branch, status: "open" }
        events << { source: "github", name: "pull_request.opened", payload: payload, timestamp: timestamp }

        # Generate check run events for PR (80% chance)
        if rand < 0.8
          check_start = timestamp + (rand(1..3) * 60) # minutes converted to seconds
          payload = github_check_run_payload("created", "in_progress", nil, repository, repo_owner, check_start,
                                             source_branch)
          events << { source: "github", name: "check_run", payload: payload, timestamp: check_start }

          check_end = check_start + (rand(2..10) * 60) # minutes converted to seconds
          conclusion = rand < 0.85 ? "success" : "failure" # 85% success rate
          payload = github_check_run_payload("completed", "completed", conclusion, repository, repo_owner, check_end,
                                             source_branch)
          events << { source: "github", name: "check_run", payload: payload, timestamp: check_end }
        end
      else
        # Fallback to push if no branches available
        payload = github_push_payload(repository, repo_owner, timestamp, "main")
        events << { source: "github", name: "push", payload: payload, timestamp: timestamp }
      end

    when :pr_close
      # Can only close PR if we have open PRs
      open_prs = pull_requests[repository].select { |pr| pr[:status] == "open" }
      if open_prs.any?
        pr = open_prs.sample
        pr[:status] = "closed"
        payload = github_pull_request_payload("closed", repository, repo_owner, timestamp, pr[:branch])
        events << { source: "github", name: "pull_request.closed", payload: payload, timestamp: timestamp }
      elsif branches[repository].size > 1
        # Fallback to creating a PR
        source_branch = (branches[repository] - ["main"]).sample
        payload = github_pull_request_payload("opened", repository, repo_owner, timestamp, source_branch)
        pr_id = payload[:number]
        pull_requests[repository] << { id: pr_id, branch: source_branch, status: "open" }
        events << { source: "github", name: "pull_request.opened", payload: payload, timestamp: timestamp }
      else
        # Or just push
        payload = github_push_payload(repository, repo_owner, timestamp, "main")
        events << { source: "github", name: "push", payload: payload, timestamp: timestamp }
      end

    when :pr_merge
      # Can only merge PR if we have open PRs
      open_prs = pull_requests[repository].select { |pr| pr[:status] == "open" }
      if open_prs.any?
        pr = open_prs.sample
        pr[:status] = "merged"
        payload = github_pull_request_payload("closed", repository, repo_owner, timestamp, pr[:branch])
        payload[:pull_request][:merged] = true
        payload[:pull_request][:merged_at] = timestamp.strftime("%Y-%m-%dT%H:%M:%SZ")
        events << { source: "github", name: "pull_request.closed", payload: payload, timestamp: timestamp }

        # After PR merge, often deploy (60% chance)
        if rand < 0.6
          # First create workflow run for deployment
          workflow_start = timestamp + (rand(1..3) * 60) # minutes converted to seconds
          workflow_payload = github_workflow_run_payload("completed", "completed", "success", repository, repo_owner,
                                                         workflow_start)
          events << { source: "github", name: "workflow_run", payload: workflow_payload, timestamp: workflow_start }

          # Then create deployment
          deploy_time = workflow_start + (rand(2..5) * 60) # minutes converted to seconds
          environment = rand < 0.7 ? "staging" : "production" # 70% to staging, 30% to production
          deploy_payload = github_deployment_payload(repository, repo_owner, deploy_time, environment)
          events << { source: "github", name: "deployment", payload: deploy_payload, timestamp: deploy_time }

          # Track lead time for changes
          lead_time_hours = ((deploy_time - timestamp) / 3600).round(2) # Convert to hours
          lead_time_payload = {
            metric_name: "ci.lead_time",
            value: lead_time_hours * 3600, # Store in seconds for consistency
            source: "github",
            dimensions: { repository: repository }
          }
          events << { source: "metrics", name: "ci.lead_time", payload: lead_time_payload, timestamp: deploy_time }

          # Then update deployment status
          status_time = deploy_time + (rand(1..5) * 60) # minutes converted to seconds
          status = rand < 0.9 ? "success" : "failure" # 90% success rate
          status_payload = github_deployment_status_payload(repository, repo_owner, status_time, environment, status)
          events << { source: "github", name: "deployment_status", payload: status_payload, timestamp: status_time }

          # Add deployment metrics for DORA
          ci_payload = ci_event_payload("deploy", status == "success" ? "completed" : "failed", repository,
                                        deploy_time, status_time)
          events << { source: "ci", name: "ci.deploy.#{status == 'success' ? 'completed' : 'failed'}",
                      payload: ci_payload, timestamp: status_time }

          # If failure, add incident metrics (for MTTR calculations)
          if status == "failure"
            # Create an incident
            incident_start = status_time
            incident_duration = rand(30..480) * 60 # minutes converted to seconds
            incident_end = incident_start + incident_duration

            resolution_payload = {
              metric_name: "incident.resolution_time",
              value: incident_duration.to_i,
              source: "monitoring",
              dimensions: {
                repository: repository,
                environment: environment,
                severity: ["critical", "major", "minor"].sample
              }
            }
            events << { source: "metrics", name: "incident.resolution_time", payload: resolution_payload,
                        timestamp: incident_end }
          end
        end
      elsif branches[repository].size > 1
        # Fallback to creating a PR
        source_branch = (branches[repository] - ["main"]).sample
        payload = github_pull_request_payload("opened", repository, repo_owner, timestamp, source_branch)
        pr_id = payload[:number]
        pull_requests[repository] << { id: pr_id, branch: source_branch, status: "open" }
        events << { source: "github", name: "pull_request.opened", payload: payload, timestamp: timestamp }
      else
        # Or just push
        payload = github_push_payload(repository, repo_owner, timestamp, "main")
        events << { source: "github", name: "push", payload: payload, timestamp: timestamp }
      end

    when :check_run
      branch = branches[repository].sample || "main"
      status = ["in_progress", "completed"].sample
      conclusion = if status == "completed"
                     rand < 0.85 ? "success" : "failure"
                   else
                     nil
                   end
      payload = github_check_run_payload(status == "in_progress" ? "created" : "completed", status, conclusion,
                                         repository, repo_owner, timestamp, branch)
      events << { source: "github", name: "check_run", payload: payload, timestamp: timestamp }

    when :workflow_run
      branch = branches[repository].sample || "main"
      status = ["in_progress", "completed"].sample
      conclusion = if status == "completed"
                     rand < 0.85 ? "success" : "failure"
                   else
                     nil
                   end
      payload = github_workflow_run_payload(status == "in_progress" ? "requested" : "completed", status, conclusion,
                                            repository, repo_owner, timestamp, branch)
      events << { source: "github", name: "workflow_run", payload: payload, timestamp: timestamp }

    when :deployment
      environment = rand < 0.7 ? "staging" : "production"
      payload = github_deployment_payload(repository, repo_owner, timestamp, environment)
      events << { source: "github", name: "deployment", payload: payload, timestamp: timestamp }

    when :deploy_status
      environment = rand < 0.7 ? "staging" : "production"
      state = ["success", "failure", "in_progress"].sample
      payload = github_deployment_status_payload(repository, repo_owner, timestamp, environment, state)
      events << { source: "github", name: "deployment_status", payload: payload, timestamp: timestamp }

      # Add DORA metrics for deployments
      if ["success", "failure"].include?(state)
        ci_start = timestamp - (rand(1..10) * 60) # minutes converted to seconds
        ci_payload = ci_event_payload("deploy", state == "success" ? "completed" : "failed", repository, ci_start,
                                      timestamp)
        events << { source: "ci", name: "ci.deploy.#{state == 'success' ? 'completed' : 'failed'}",
                    payload: ci_payload, timestamp: timestamp }
      end
    end
  end

  # Sort events by timestamp
  events.sort_by { |e| e[:timestamp] }
end

# Generate a GitHub issue payload
def github_issue_payload(action, repository_name, repo_owner, timestamp, issue_number = nil)
  issue_number ||= rand(1..500)
  issue_states = ["open", "closed"]
  issue_state = action == "closed" ? "closed" : "open"
  issue_labels = ["bug", "feature", "enhancement", "documentation", "refactor", "technical-debt", "security"]
  selected_labels = issue_labels.sample(rand(0..3))

  {
    action: action,
    issue: {
      url: "https://api.github.com/repos/#{repo_owner}/#{repository_name}/issues/#{issue_number}",
      id: rand(100_000..999_999),
      number: issue_number,
      title: ["Implement new feature", "Fix critical bug", "Refactor authentication code",
              "Update API documentation", "Optimize database queries", "Improve UI responsiveness",
              "Add unit tests", "Fix security vulnerability"].sample,
      user: {
        login: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
        id: rand(1000..9999)
      },
      labels: selected_labels.map do |name|
        {
          name: name,
          color: SecureRandom.hex(3)
        }
      end,
      state: issue_state,
      assignee: if rand > 0.3
                  {
                    login: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
                    id: rand(1000..9999)
                  }
                else
                  nil
                end,
      milestone: if rand > 0.5
                   {
                     title: ["v1.0", "v1.1", "Q2 Goals", "Sprint 12", "Backend Refactor"].sample,
                     number: rand(1..20),
                     state: ["open", "closed"].sample
                   }
                 else
                   nil
                 end,
      created_at: (timestamp - (rand(1..168) * 3600)).strftime("%Y-%m-%dT%H:%M:%SZ"), # hours converted to seconds (up to a week ago)
      updated_at: timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"),
      closed_at: action == "closed" ? timestamp.strftime("%Y-%m-%dT%H:%M:%SZ") : nil,
      body: "This issue is related to an important task that needs attention. Please address it according to our guidelines."
    },
    repository: {
      id: rand(100_000..999_999),
      name: repository_name,
      full_name: "#{repo_owner}/#{repository_name}",
      owner: {
        login: repo_owner,
        id: rand(1000..9999)
      }
    },
    sender: {
      login: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
      id: rand(1000..9999)
    }
  }
end

# Generate a GitHub project card payload
def github_project_card_payload(action, repository_name, repo_owner, timestamp, content_type = "Issue",
                                column_name = nil)
  project_id = rand(1000..9999)
  column_id = rand(10_000..99_999)
  card_id = rand(100_000..999_999)
  content_id = rand(100_000..999_999)

  # Project columns for typical engineering workflow
  columns = ["To Do", "In Progress", "Code Review", "QA", "Done"]
  column_name ||= columns.sample

  content_url = if content_type == "Issue"
                  "https://api.github.com/repos/#{repo_owner}/#{repository_name}/issues/#{rand(1..100)}"
                else
                  "https://api.github.com/repos/#{repo_owner}/#{repository_name}/pulls/#{rand(1..100)}"
                end

  {
    action: action,
    project_card: {
      id: card_id,
      url: "https://api.github.com/projects/columns/cards/#{card_id}",
      project_url: "https://api.github.com/projects/#{project_id}",
      column_id: column_id,
      column_name: column_name,
      created_at: (timestamp - (rand(1..72) * 3600)).strftime("%Y-%m-%dT%H:%M:%SZ"), # hours converted to seconds (up to 3 days ago)
      updated_at: timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"),
      content_url: content_url,
      content_type: content_type,
      creator: {
        login: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
        id: rand(1000..9999)
      }
    },
    repository: {
      id: rand(100_000..999_999),
      name: repository_name,
      full_name: "#{repo_owner}/#{repository_name}",
      owner: {
        login: repo_owner,
        id: rand(1000..9999)
      }
    },
    sender: {
      login: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
      id: rand(1000..9999)
    }
  }
end

# Generate a task event payload for internal tracking
def task_event_payload(action, repository_name, issue_number, timestamp)
  {
    repository: repository_name,
    issue_number: issue_number,
    action: action,
    type: ["feature", "bug", "enhancement", "refactor", "documentation"].sample,
    project: ["Engineering Backlog", "Q2 Goals", "Current Sprint"].sample,
    points: rand(1..5),
    assigned_to: ["alice", "bob", "charlie", "dana", "evan", "frank", "grace", "hector"].sample,
    timestamp: timestamp.strftime("%Y-%m-%dT%H:%M:%SZ")
  }
end

# Generate a week of engineering project progress
def generate_project_progress_events(days = 14)
  events = []
  repositories = ["api-service", "frontend", "data-processor", "auth-service", "monitoring-tools"]
  repo_owner = "acme"

  # Define time range (14 days ago until now)
  end_time = Time.now.utc
  start_time = end_time - (days * 24 * 60 * 60)

  # Track issues and their current state
  issues = Hash.new { |h, k| h[k] = [] }

  # Create initial set of issues and put them in To Do
  repositories.each do |repo|
    # Create 3-8 issues per repository
    issue_count = rand(3..8)
    issue_count.times do
      issue_number = rand(1..500)
      created_time = random_time_in_range(start_time, start_time + (days * 0.3 * 24 * 60 * 60)) # First 30% of time period

      # Create issue
      issue_payload = github_issue_payload("opened", repo, repo_owner, created_time, issue_number)
      events << { source: "github", name: "issues.opened", payload: issue_payload, timestamp: created_time }

      # Track issue
      issues[repo] << {
        number: issue_number,
        state: "open",
        column: "To Do",
        created_at: created_time
      }

      # Add task metrics for team velocity
      task_payload = task_event_payload("created", repo, issue_number, created_time)
      events << { source: "task", name: "task.created", payload: task_payload, timestamp: created_time }

      # Add to project board (To Do column)
      card_payload = github_project_card_payload("created", repo, repo_owner, created_time, "Issue", "To Do")
      events << { source: "github", name: "project_card.created", payload: card_payload, timestamp: created_time }
    end
  end

  # Process each day - move issues through the workflow
  (1...days).each do |day|
    day_start = start_time + (day * 24 * 60 * 60)
    day_end = day_start + (24 * 60 * 60)

    # Each day, process some issues (move them forward in the workflow)
    repositories.each do |repo|
      # Get the issues for this repo
      repo_issues = issues[repo]

      # Process a random number of issues each day
      issue_count = [repo_issues.count, rand(1..4)].min
      issue_count.times do
        # Select a random issue that isn't completed
        active_issues = repo_issues.select { |i| i[:column] != "Done" && i[:state] != "closed" }
        next if active_issues.empty?

        issue = active_issues.sample
        event_time = random_time_in_range(day_start, day_end)

        # Determine the next state based on current state
        case issue[:column]
        when "To Do"
          # Move to In Progress
          issue[:column] = "In Progress"

          # Create project card moved event
          card_payload = github_project_card_payload("moved", repo, repo_owner, event_time, "Issue", "In Progress")
          events << { source: "github", name: "project_card.moved", payload: card_payload, timestamp: event_time }

          # Create task moved event for internal tracking
          task_payload = task_event_payload("moved", repo, issue[:number], event_time)
          events << { source: "task", name: "task.moved", payload: task_payload, timestamp: event_time }

        when "In Progress"
          # Move to Code Review
          issue[:column] = "Code Review"

          # Create project card moved event
          card_payload = github_project_card_payload("moved", repo, repo_owner, event_time, "Issue", "Code Review")
          events << { source: "github", name: "project_card.moved", payload: card_payload, timestamp: event_time }

          # Create task moved event for internal tracking
          task_payload = task_event_payload("moved", repo, issue[:number], event_time)
          events << { source: "task", name: "task.moved", payload: task_payload, timestamp: event_time }

          # 80% chance to create a PR for this issue
          if rand < 0.8
            # Add a small delay for PR creation after the card is moved
            pr_time = event_time + (rand(10..60) * 60) # 10-60 minutes later
            branch_name = "fix/issue-#{issue[:number]}"
            pr_payload = github_pull_request_payload("opened", repo, repo_owner, pr_time, branch_name)
            events << { source: "github", name: "pull_request.opened", payload: pr_payload, timestamp: pr_time }
          end

        when "Code Review"
          if rand < 0.8 # 80% chance to move to QA
            # Move to QA
            issue[:column] = "QA"

            # Create project card moved event
            card_payload = github_project_card_payload("moved", repo, repo_owner, event_time, "Issue", "QA")
            events << { source: "github", name: "project_card.moved", payload: card_payload, timestamp: event_time }

            # Create task moved event for internal tracking
            task_payload = task_event_payload("moved", repo, issue[:number], event_time)
            events << { source: "task", name: "task.moved", payload: task_payload, timestamp: event_time }
          end

        when "QA"
          if rand < 0.9 # 90% chance to move to Done
            # Move to Done
            issue[:column] = "Done"
            issue[:state] = "closed"

            # Create project card moved event
            card_payload = github_project_card_payload("moved", repo, repo_owner, event_time, "Issue", "Done")
            events << { source: "github", name: "project_card.moved", payload: card_payload, timestamp: event_time }

            # Close the issue
            issue_payload = github_issue_payload("closed", repo, repo_owner, event_time, issue[:number])
            events << { source: "github", name: "issues.closed", payload: issue_payload, timestamp: event_time }

            # Create task completed event for internal tracking
            task_payload = task_event_payload("completed", repo, issue[:number], event_time)
            events << { source: "task", name: "task.completed", payload: task_payload, timestamp: event_time }
          end
        end
      end
    end
  end

  # Sort events by timestamp
  events.sort_by { |e| e[:timestamp] }
end

# Only run the script when it's called directly, not when required/loaded
if __FILE__ == $PROGRAM_NAME
  # Print intro
  puts "ReflexAgent Webhook Demo - Enhanced GitHub Engineering Workflow"
  puts "=============================================================="
  puts "Configuration:"
  puts "  Events Count: #{EVENTS_COUNT}"
  puts "  Days to Simulate: #{DAYS_TO_SIMULATE}"
  puts "  Batch Size: #{BATCH_SIZE}"
  puts "  Send Delay: #{SEND_DELAY}s"
  puts "  Team Size: #{TEAM_SIZE}"
  puts "  Webhook URL: #{BASE_URL}/events"
  puts "=============================================================="
  puts "Generating engineering workflow events..."

  # Generate events
  workflow_events = generate_engineering_workflow_events(EVENTS_COUNT, DAYS_TO_SIMULATE)
  project_events = generate_project_progress_events(DAYS_TO_SIMULATE)
  combined_events = (workflow_events + project_events).sort_by { |e| e[:timestamp] }

  puts "Generated #{workflow_events.size} workflow events spanning #{DAYS_TO_SIMULATE} days"
  puts "Generated #{project_events.size} project management events spanning #{DAYS_TO_SIMULATE} days"
  puts "Sending #{combined_events.size} total events to #{BASE_URL}/events\n\n"

  # Send events in batches
  start_time = Time.now
  batches = combined_events.each_slice(BATCH_SIZE).to_a

  batches.each_with_index do |batch, batch_index|
    batch_start = Time.now
    puts "Sending batch #{batch_index + 1}/#{batches.size} (#{batch.size} events)..."

    # Process this batch
    send_webhook_batch(batch)

    # Show batch complete and time
    batch_duration = Time.now - batch_start
    events_per_second = batch.size / batch_duration
    puts "Batch #{batch_index + 1} complete. Sent #{batch.size} events in #{batch_duration.round(2)}s (#{events_per_second.round(2)} events/s)"

    # Sleep between batches if configured
    sleep(SEND_DELAY) if SEND_DELAY > 0 && batch_index < batches.size - 1
  end

  total_duration = Time.now - start_time
  events_per_second = combined_events.size / total_duration

  puts "\nAll done! Sent #{combined_events.size} events in #{total_duration.round(2)}s"
  puts "Average rate: #{events_per_second.round(2)} events/s"
  puts "Check your application logs for details on processing."
end
