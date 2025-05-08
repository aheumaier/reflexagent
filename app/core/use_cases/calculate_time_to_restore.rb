# frozen_string_literal: true

module UseCases
  # CalculateTimeToRestore calculates time to recover from incidents and determines DORA rating
  class CalculateTimeToRestore
    def initialize(storage_port:, logger_port: nil)
      @storage_port = storage_port
      @logger_port = logger_port
    end

    # @param time_period [Integer] The number of days to look back
    # @return [Hash] Time to restore metrics with DORA rating
    def call(time_period:)
      start_time = time_period.days.ago
      log_info("Calculating time to restore service for past #{time_period} days")

      # First try looking for the specific DORA time to restore metric
      ttr_metrics = @storage_port.list_metrics(
        name: "dora.time_to_restore",
        start_time: start_time
      )

      # If no metrics found, try looking for hourly metrics
      if ttr_metrics.empty?
        log_info("No dora.time_to_restore metrics found, checking hourly metrics")
        ttr_metrics = @storage_port.list_metrics(
          name: "dora.time_to_restore.hourly",
          start_time: start_time
        )
      end

      # If still no metrics, check for 5min metrics
      if ttr_metrics.empty?
        log_info("No hourly time to restore metrics found, checking 5min metrics")
        ttr_metrics = @storage_port.list_metrics(
          name: "dora.time_to_restore.5min",
          start_time: start_time
        )
      end

      log_info("Found #{ttr_metrics.count} time to restore metrics")

      if ttr_metrics.any?
        # Calculate average time to restore in hours
        # Time is stored in seconds, convert to hours for evaluation
        total_ttr_seconds = ttr_metrics.sum(&:value)
        avg_ttr_hours = (total_ttr_seconds / ttr_metrics.size / 3600.0).round(2)

        rating = determine_rating(avg_ttr_hours)

        log_info("Average time to restore: #{avg_ttr_hours} hours, Rating: #{rating}")

        {
          value: avg_ttr_hours,
          rating: rating,
          sample_size: ttr_metrics.size
        }
      else
        log_warn("No time to restore metrics found - returning 'unknown' rating")

        {
          value: 0,
          rating: "unknown",
          sample_size: 0
        }
      end
    end

    private

    # Determine DORA rating for restore time
    # @param hours [Float] Restore time in hours
    # @return [String] Rating category (elite, high, medium, low)
    def determine_rating(hours)
      if hours < 1
        "elite"       # Less than one hour
      elsif hours < 24
        "high"        # Less than one day
      elsif hours < 168
        "medium"      # Less than one week
      else
        "low"         # More than one week
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
