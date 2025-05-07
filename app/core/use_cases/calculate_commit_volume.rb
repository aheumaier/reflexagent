# frozen_string_literal: true

module UseCases
  # CalculateCommitVolume computes commit frequency and daily activity metrics
  class CalculateCommitVolume
    def initialize(storage_port:, cache_port: nil)
      @storage_port = storage_port
      @cache_port = cache_port
    end

    # @param repository [String, nil] Optional repository to filter by
    # @param time_period [Integer] The number of days to look back
    # @return [Hash] Commit volume metrics with time series data
    def call(time_period:, repository: nil)
      # Implementation will be added later
      {
        total_commits: 0,
        days_with_commits: 0,
        days_analyzed: time_period,
        commits_per_day: 0,
        commit_frequency: 0,
        daily_activity: []
      }
    end

    private

    # Get cache key for storing commit volume metrics
    # @param repository [String, nil] Repository name or nil
    # @param time_period [Integer] Time period in days
    # @return [String] Cache key
    def cache_key(repository, time_period)
      parts = ["commit_volume"]
      parts << repository if repository
      parts << "days_#{time_period}"
      parts.join(":")
    end
  end
end
