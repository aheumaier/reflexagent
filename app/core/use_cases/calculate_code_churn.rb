# frozen_string_literal: true

module UseCases
  # CalculateCodeChurn measures code additions and deletions
  class CalculateCodeChurn
    def initialize(storage_port:, cache_port: nil)
      @storage_port = storage_port
      @cache_port = cache_port
    end

    # @param repository [String, nil] Optional repository to filter by
    # @param time_period [Integer] The number of days to look back
    # @return [Hash] Code churn metrics (additions, deletions, churn ratio)
    def call(time_period:, repository: nil)
      # Implementation will be added later
      {
        additions: 0,
        deletions: 0,
        total_churn: 0,
        churn_ratio: 0
      }
    end

    private

    # Get cache key for storing code churn metrics
    # @param repository [String, nil] Repository name or nil
    # @param time_period [Integer] Time period in days
    # @return [String] Cache key
    def cache_key(repository, time_period)
      parts = ["code_churn"]
      parts << repository if repository
      parts << "days_#{time_period}"
      parts.join(":")
    end
  end
end
