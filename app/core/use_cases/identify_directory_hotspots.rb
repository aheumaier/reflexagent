# frozen_string_literal: true

module UseCases
  # IdentifyDirectoryHotspots finds which directories have the most changes in a repository
  class IdentifyDirectoryHotspots
    def initialize(storage_port:, cache_port: nil)
      @storage_port = storage_port
      @cache_port = cache_port
    end

    # @param repository [String, nil] Optional repository to filter by
    # @param time_period [Integer] The number of days to look back
    # @param limit [Integer] Maximum number of directories to return
    # @return [Array<Hash>] Directory hotspots with change counts
    def call(time_period:, repository: nil, limit: 10)
      # Implementation will be added later
      []
    end

    private

    # Get cache key for storing directory hotspots
    # @param repository [String, nil] Repository name or nil
    # @param time_period [Integer] Time period in days
    # @param limit [Integer] Result limit
    # @return [String] Cache key
    def cache_key(repository, time_period, limit)
      parts = ["directory_hotspots"]
      parts << repository if repository
      parts << "days_#{time_period}"
      parts << "limit_#{limit}"
      parts.join(":")
    end
  end
end
