#!/usr/bin/env ruby
# frozen_string_literal: true

# This script checks how the dashboard will display the commit date metrics
# Run with: rails runner script/check_commit_date_dashboard.rb

puts "🔍 Checking commit date metrics for dashboard..."
puts "=" * 80

# Get access to the dashboard adapter
dashboard_adapter = DependencyContainer.resolve(:dashboard_adapter)

# Get repository metrics for the past 30 days
repository_metrics = dashboard_adapter.get_repository_metrics(time_period: 30)

puts "📊 REPOSITORY METRICS FROM DASHBOARD ADAPTER:"
puts "-" * 80

# Show commit volume by date
commit_volume = repository_metrics[:commit_volume]
puts "Commit volume data:"
puts "  Total commits: #{commit_volume.values.sum}"

if commit_volume.any?
  puts "  Commits by date:"
  commit_volume.sort_by { |date, _| date }.each do |date, count|
    puts "    #{date}: #{count}"
  end
else
  puts "  No commit volume data found"
end

# Show active repositories
active_repos = repository_metrics[:active_repos]
puts "\nActive repositories:"
if active_repos.any?
  active_repos.sort_by { |_, count| -count }.each do |repo, count|
    puts "  #{repo}: #{count} commits"
  end
else
  puts "  No active repositories found"
end

# Direct query of the metrics to verify
puts "\n📋 DIRECT QUERY OF METRICS IN DATABASE:"
puts "-" * 80
metric_repository = DependencyContainer.resolve(:metric_repository)

daily_commit_metrics = metric_repository.list_metrics(
  name: "github.commit_volume.daily",
  start_time: 30.days.ago
)

puts "Found #{daily_commit_metrics.count} github.commit_volume.daily metrics"
if daily_commit_metrics.any?
  puts "\nCommit volume metrics by date:"

  # Group metrics by date
  metrics_by_date = daily_commit_metrics.group_by { |m| m.dimensions["date"] }

  metrics_by_date.sort.each do |date, metrics|
    total_for_date = metrics.sum(&:value)
    puts "  #{date}: #{total_for_date} commits from #{metrics.size} metric(s)"

    # Show individual metrics
    metrics.each do |metric|
      puts "    ID: #{metric.id}, Value: #{metric.value}, Repository: #{metric.dimensions['repository']}, Recorded: #{metric.recorded_at}"
    end
  end
else
  puts "No github.commit_volume.daily metrics found in database"
end
