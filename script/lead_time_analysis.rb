#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to demonstrate the enhanced CalculateLeadTime functionality
# Run with: rails runner script/lead_time_analysis.rb

# Create logger
logger = Logger.new(STDOUT)
logger.level = Logger::INFO

# Get required ports
metric_repository = DependencyContainer.resolve(:metric_repository)

# Print header
logger.info "========================================================"
logger.info "    Lead Time for Changes - Comprehensive Analysis"
logger.info "========================================================"

# Create the use case
calculate_lead_time = UseCases::CalculateLeadTime.new(
  storage_port: metric_repository,
  logger_port: logger
)

# Define time periods to analyze
time_periods = [7, 30, 90]
percentiles = [nil, 50, 75, 95]

# For each time period
time_periods.each do |days|
  logger.info "\n====== Analysis for past #{days} days ======\n"

  # Standard calculation (average)
  result = calculate_lead_time.call(
    time_period: days,
    breakdown: true
  )

  logger.info "Basic Analysis:"
  logger.info "  Lead time: #{result[:value]} hours"
  logger.info "  DORA rating: #{result[:rating]}"
  logger.info "  Sample size: #{result[:sample_size]} changes"

  # Process breakdown if available
  if result[:breakdown].present?
    logger.info "\nProcess Breakdown:"
    result[:breakdown].each do |stage, hours|
      logger.info "  #{stage.to_s.humanize}: #{hours} hours (#{(hours / result[:value] * 100).round(1)}%)"
    end
  end

  # Percentile calculations
  [50, 75, 95].each do |percentile|
    percentile_result = calculate_lead_time.call(
      time_period: days,
      percentile: percentile
    )

    next unless percentile_result[:percentile]

    logger.info "\n#{percentile}th Percentile Analysis:"
    logger.info "  Lead time (#{percentile}th percentile): #{percentile_result[:percentile][:value]} hours"
    logger.info "  DORA rating based on #{percentile}th percentile: #{percentile_result[:rating]}"
  end

  logger.info "\n----------------------------------------------"
end

# DORA Rating Table
logger.info "\n========================================================"
logger.info "    DORA Performance Categories for Lead Time"
logger.info "========================================================"
logger.info "  Elite:  Less than 24 hours (1 day)"
logger.info "  High:   Between 24 hours and 168 hours (1 week)"
logger.info "  Medium: Between 168 hours and 730 hours (1 month)"
logger.info "  Low:    More than 730 hours (1 month)"
logger.info "========================================================\n"

# Additional recommendations
logger.info "Recommendations:"
logger.info "1. Consider using the 75th or 95th percentile instead of the average"
logger.info "   to better account for outliers in your lead time measurements."
logger.info "2. Track lead time trends over time to see if your delivery process"
logger.info "   is improving or needs attention."
logger.info "3. Use the process breakdown information to identify bottlenecks"
logger.info "   in your delivery pipeline."
logger.info "4. Compare lead times across different teams or projects to"
logger.info "   identify best practices."
logger.info "5. Set improvement targets based on the DORA benchmarks."

logger.info "\nRun individual analyses with:"
logger.info "  rails runner script/calculate_lead_time.rb [DAYS] [PERCENTILE] [save]"
