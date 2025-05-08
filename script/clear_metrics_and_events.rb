#!/usr/bin/env ruby
# frozen_string_literal: true

# This script clears metrics and events from the database without requiring a full db:reset
# Run with: rails runner script/clear_metrics_and_events.rb

puts "🗑️  Clearing metrics and events from the database..."
puts "===================================================="

metrics_count = DomainMetric.count
puts "Found #{metrics_count} metrics"

events_count = DomainEvent.count
puts "Found #{events_count} events"

puts "\nDeleting all metrics..."
DomainMetric.delete_all
puts "✅ All metrics deleted."

puts "\nDeleting all events..."
DomainEvent.delete_all
puts "✅ All events deleted."

puts "\nResetting sequences for main tables..."
# Only reset sequences for the main tables, not for partitioned tables
["domain_events", "domain_alerts"].each do |table_name|
  next unless ActiveRecord::Base.connection.table_exists?(table_name) &&
              ActiveRecord::Base.connection.column_exists?(table_name, "id")

  ActiveRecord::Base.connection.execute("ALTER SEQUENCE #{table_name}_id_seq RESTART WITH 1")
  puts "Reset sequence for #{table_name}"
end

puts "\n🧹 Cleanup complete!"
puts "You can now run demo_events.rb to load fresh data."
