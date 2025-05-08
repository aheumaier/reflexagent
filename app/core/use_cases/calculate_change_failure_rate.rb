# frozen_string_literal: true

module UseCases
  # CalculateChangeFailureRate calculates percentage of deployments causing incidents and determines DORA rating
  class CalculateChangeFailureRate
    def initialize(storage_port:, logger_port: nil)
      @storage_port = storage_port
      @logger_port = logger_port
    end

    # @param time_period [Integer] The number of days to look back
    # @return [Hash] Change failure rate metrics with DORA rating
    def call(time_period:)
      start_time = time_period.days.ago
      log_info("Calculating change failure rate for past #{time_period} days")

      # First try looking for the specific DORA change failure rate metric
      cfr_metrics = @storage_port.list_metrics(
        name: "dora.change_failure_rate",
        start_time: start_time
      )

      # If no metrics found, try looking for hourly metrics
      if cfr_metrics.empty?
        log_info("No dora.change_failure_rate metrics found, checking hourly metrics")
        cfr_metrics = @storage_port.list_metrics(
          name: "dora.change_failure_rate.hourly",
          start_time: start_time
        )
      end

      # If still no metrics, check for 5min metrics
      if cfr_metrics.empty?
        log_info("No hourly change failure rate metrics found, checking 5min metrics")
        cfr_metrics = @storage_port.list_metrics(
          name: "dora.change_failure_rate.5min",
          start_time: start_time
        )
      end

      log_info("Found #{cfr_metrics.count} change failure rate metrics")

      if cfr_metrics.any?
        # Get the most recent metric since this is a percentage
        latest_metric = cfr_metrics.max_by(&:timestamp)
        failure_rate = latest_metric.value

        # Extract failures and deployments from dimensions if available
        failures = latest_metric.dimensions["failures"].to_i
        deployments = latest_metric.dimensions["deployments"].to_i

        # Default values if dimensions not available
        failures = 0 if failures <= 0
        deployments = 1 if deployments <= 0

        rating = determine_rating(failure_rate)

        log_info("Change failure rate: #{failure_rate}%, Rating: #{rating}")

        {
          value: failure_rate,
          rating: rating,
          failures: failures,
          deployments: deployments
        }
      else
        log_warn("No change failure rate metrics found - returning 'unknown' rating")

        {
          value: 0,
          rating: "unknown",
          failures: 0,
          deployments: 0
        }
      end
    end

    private

    # Determine DORA rating for change failure rate
    # @param percentage [Float] Failure rate percentage
    # @return [String] Rating category (elite, high, medium, low)
    def determine_rating(percentage)
      if percentage <= 0.15
        "elite"       # 0-15%
      elsif percentage <= 0.30
        "high"        # 16-30%
      elsif percentage <= 0.45
        "medium"      # 31-45%
      else
        "low"         # 46-100%
      end
    end

    def log_info(message)
      @logger_port&.info(message)
    end

    def log_warn(message)
      @logger_port&.warn(message)
    end
  end
end
