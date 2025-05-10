#!/usr/bin/env ruby
# frozen_string_literal: true

# This script debugs the repository metrics calculation for commits
# Run with: rails runner script/debug_repository_metrics.rb

puts "🔍 Debugging repository metrics calculation..."
puts "=" * 80

# Get access to the metric repository and dashboard adapter
metric_repository = DependencyContainer.resolve(:metric_repository)
dashboard_adapter = DependencyContainer.resolve(:dashboard_adapter)

# Define time period (30 days)
time_period = 30
start_time = time_period.days.ago

# Check for github.push.commits metrics
puts "\n📊 CHECKING GITHUB.PUSH.COMMITS METRICS:"
puts "-" * 80

commit_metrics = metric_repository.list_metrics(
  name: "github.push.commits",
  start_time: start_time
)

puts "Found #{commit_metrics.count} github.push.commits metrics"

# Group by repository
commits_by_repo = commit_metrics.group_by { |m| m.dimensions["repository"] || "unknown" }
                                .transform_values { |metrics| metrics.sum(&:value) }
                                .sort_by { |_, count| -count }
                                .to_h

puts "\nCommits by repository:"
if commits_by_repo.any?
  commits_by_repo.each do |repo, count|
    puts "  #{repo}: #{count.to_i} commits"
  end
else
  puts "  No repository data found"
end

# Get the repository metrics from the dashboard adapter
puts "\n📊 GETTING REPOSITORY METRICS FROM DASHBOARD ADAPTER:"
puts "-" * 80

repo_metrics = dashboard_adapter.get_repository_metrics(time_period: time_period)

puts "Active repositories from dashboard adapter:"
if repo_metrics[:active_repos].any?
  repo_metrics[:active_repos].each do |repo, count|
    puts "  #{repo}: #{count} pushes"
  end
else
  puts "  No active repositories found"
end

puts "\nCommit volume data:"
if repo_metrics[:commit_volume].is_a?(Hash) && repo_metrics[:commit_volume].any?
  puts "  Total commits: #{repo_metrics[:commit_volume].values.sum}"
  repo_metrics[:commit_volume].each do |date, count|
    puts "  #{date}: #{count} commits"
  end
else
  puts "  Empty commit volume data: #{repo_metrics[:commit_volume].inspect}"
end

# Call the calculate_commit_volume use case directly
puts "\n📊 CALLING CALCULATE_COMMIT_VOLUME USE CASE DIRECTLY:"
puts "-" * 80

calculate_commit_volume = UseCases::CalculateCommitVolume.new(
  storage_port: metric_repository,
  cache_port: nil
)

# Try for each repository
if commits_by_repo.any?
  repo_name = commits_by_repo.keys.first
  puts "Checking commit volume for repository: #{repo_name}"
  result = calculate_commit_volume.call(repository: repo_name, time_period: time_period)
  puts "Result: #{result.inspect}"
else
  puts "Checking commit volume for all repositories"
  result = calculate_commit_volume.call(time_period: time_period)
  puts "Result: #{result.inspect}"
end

# Check for any github.push.total metrics
puts "\n📊 CHECKING GITHUB.PUSH.TOTAL METRICS:"
puts "-" * 80

push_metrics = metric_repository.list_metrics(
  name: "github.push.total",
  start_time: start_time
)

puts "Found #{push_metrics.count} github.push.total metrics"
if push_metrics.any?
  push_by_repo = push_metrics.group_by { |m| m.dimensions["repository"] || "unknown" }
                             .transform_values(&:count)
                             .sort_by { |_, count| -count }
                             .to_h

  puts "\nPushes by repository:"
  push_by_repo.each do |repo, count|
    puts "  #{repo}: #{count} pushes"
  end
end

puts "\n✅ Debug complete!"
