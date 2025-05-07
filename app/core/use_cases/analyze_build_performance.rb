# frozen_string_literal: true

module UseCases
  # AnalyzeBuildPerformance tracks build success rates and durations
  class AnalyzeBuildPerformance
    def initialize(storage_port:, cache_port: nil)
      @storage_port = storage_port
      @cache_port = cache_port
    end

    # @param time_period [Integer] The number of days to look back
    # @return [Hash] Build performance metrics
    def call(time_period:)
      # Implementation will be added later
      {
        builds_by_day: {},
        total_builds: 0,
        average_build_duration: 0,
        success_rate: 0
      }
    end

    private

    # Get cache key for storing build performance metrics
    # @param time_period [Integer] Time period in days
    # @return [String] Cache key
    def cache_key(time_period)
      "build_performance:days_#{time_period}"
    end
  end
end
