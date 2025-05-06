#!/usr/bin/env ruby
# frozen_string_literal: true

# This script tests if the CommitMetricsController can retrieve directory and filetype metrics correctly

# Create a controller instance
controller = Dashboards::CommitMetricsController.new

# Set the days parameter
controller.instance_variable_set(:@days, 30)

# Call the private method to fetch commit metrics
metrics = controller.send(:fetch_commit_metrics, 30)

# Print the results
puts "Directory hotspots:"
pp metrics[:directory_hotspots]

puts "\nFile extension hotspots:"
pp metrics[:file_extension_hotspots]
