#!/usr/bin/env ruby
# frozen_string_literal: true

# This script analyzes commit timestamps in GitHub events and metrics
# Run with: rails runner script/analyse_commit_timestamps.rb

puts "🔍 Analyzing commit timestamp data in events and metrics..."
puts "=" * 80

puts "\n📊 GITHUB PUSH EVENT ANALYSIS:"
puts "-" * 80

# Get GitHub push events
push_events = DomainEvent.where(event_type: "github.push.created").order(created_at: :desc).limit(10)
puts "Found #{push_events.count} github.push.created events"

# Analyze the events
event_data = []
push_events.each do |event|
  commits = event.payload.dig("commits") || []
  repository = event.payload.dig("repository", "full_name")

  commit_timestamps = commits.map do |commit|
    timestamp = commit["timestamp"]
    {
      commit_id: commit["id"],
      author: commit["author"]["name"],
      message: commit["message"].to_s.truncate(40),
      timestamp: timestamp,
      parsed_time: timestamp ? Time.parse(timestamp) : nil
    }
  end

  event_data << {
    event_id: event.id,
    repository: repository,
    event_time: event.created_at,
    commit_count: commits.size,
    commit_timestamps: commit_timestamps
  }
end

# Print event analysis
event_data.each_with_index do |data, index|
  puts "\nEvent #{index + 1}:"
  puts "  ID: #{data[:event_id]}"
  puts "  Repository: #{data[:repository]}"
  puts "  Event recorded at: #{data[:event_time]}"
  puts "  Commit count: #{data[:commit_count]}"

  next unless data[:commit_timestamps].any?

  puts "  Commit details:"
  data[:commit_timestamps].each_with_index do |commit, c_index|
    puts "    Commit #{c_index + 1}:"
    puts "      ID: #{commit[:commit_id]}"
    puts "      Author: #{commit[:author]}"
    puts "      Message: #{commit[:message]}"
    puts "      Timestamp: #{commit[:timestamp]}"

    if commit[:parsed_time] && data[:event_time]
      time_diff = data[:event_time] - commit[:parsed_time]
      puts "      Time difference: #{(time_diff / 86_400).round(2)} days"
    end
  end
end

puts "\n📊 COMMIT METRICS ANALYSIS:"
puts "-" * 80

# Get commit metrics
commit_metrics = DomainMetric.where(name: "github.push.commits").order(recorded_at: :desc).limit(10)
puts "Found #{commit_metrics.count} github.push.commits metrics"

# Analyze the metrics
commit_metrics.each_with_index do |metric, index|
  puts "\nMetric #{index + 1}:"
  puts "  ID: #{metric.id}"
  puts "  Value: #{metric.value} commits"
  puts "  Recorded at: #{metric.recorded_at}"
  puts "  Repository: #{metric.dimensions['repository']}"
  puts "  Dimensions: #{metric.dimensions}"

  # The metric doesn't contain the actual commit timestamp, just when it was recorded
  puts "  ⚠️ Note: This metric doesn't store the original commit timestamps"
end

puts "\n📝 IMPROVEMENT PLAN:"
puts "-" * 80
puts "1. Enhance github.push.commits metrics to include original commit timestamp"
puts "2. Modify CalculateCommitVolume to use original timestamps instead of event reception time"
puts "3. Update DashboardAdapter to display commits spread across their actual dates"
