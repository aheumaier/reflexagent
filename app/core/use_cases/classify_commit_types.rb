# frozen_string_literal: true

module UseCases
  # ClassifyCommitTypes categorizes commits and calculates distribution percentages
  class ClassifyCommitTypes
    def initialize(storage_port:, cache_port: nil)
      @storage_port = storage_port
      @cache_port = cache_port
    end

    # @param repository [String, nil] Optional repository to filter by
    # @param time_period [Integer] The number of days to look back
    # @param limit [Integer] Maximum number of commit types to return
    # @return [Array<Hash>] Commit types with counts and percentages
    def call(time_period:, repository: nil, limit: 10)
      # Implementation will be added later
      []
    end

    private

    # Get cache key for storing commit type classification
    # @param repository [String, nil] Repository name or nil
    # @param time_period [Integer] Time period in days
    # @param limit [Integer] Result limit
    # @return [String] Cache key
    def cache_key(repository, time_period, limit)
      parts = ["commit_types"]
      parts << repository if repository
      parts << "days_#{time_period}"
      parts << "limit_#{limit}"
      parts.join(":")
    end

    # Calculate percentage for each commit type
    # @param commit_types [Hash] Commit types with counts
    # @return [Array<Hash>] Commit types with counts and percentages
    def calculate_percentages(commit_types)
      # Implementation will be added later
      []
    end
  end
end
