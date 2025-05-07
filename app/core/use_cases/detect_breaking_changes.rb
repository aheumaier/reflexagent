# frozen_string_literal: true

module UseCases
  # DetectBreakingChanges identifies potentially disruptive commits
  class DetectBreakingChanges
    def initialize(storage_port:, cache_port: nil)
      @storage_port = storage_port
      @cache_port = cache_port
    end

    # @param repository [String, nil] Optional repository to filter by
    # @param time_period [Integer] The number of days to look back
    # @return [Hash] Breaking changes summary with author breakdown
    def call(time_period:, repository: nil)
      # Implementation will be added later
      {
        total: 0,
        by_author: []
      }
    end

    private

    # Get cache key for storing breaking changes metrics
    # @param repository [String, nil] Repository name or nil
    # @param time_period [Integer] Time period in days
    # @return [String] Cache key
    def cache_key(repository, time_period)
      parts = ["breaking_changes"]
      parts << repository if repository
      parts << "days_#{time_period}"
      parts.join(":")
    end
  end
end
