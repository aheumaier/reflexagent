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
      # Try to get from cache first
      if @cache_port && (cached_result = from_cache(repository, time_period))
        return cached_result
      end

      start_time = time_period.days.ago

      # Get all commit metrics for the time period
      commit_metrics = @storage_port.list_metrics(
        name: "github.push.commits",
        start_time: start_time
      )

      # Filter by repository if specified
      if repository.present?
        commit_metrics = commit_metrics.select do |metric|
          metric.dimensions["repository"] == repository
        end
      end

      # If no metrics found, return empty result
      if commit_metrics.empty?
        result = {
          total_commits: 0,
          days_with_commits: 0,
          days_analyzed: time_period,
          commits_per_day: 0,
          commit_frequency: 0,
          daily_activity: []
        }

        # Cache the result if caching is enabled
        cache_result(repository, time_period, result) if @cache_port

        return result
      end

      # Sum up the total number of commits
      total_commits = commit_metrics.sum(&:value)

      # Group metrics by day to calculate daily activity
      daily_metrics = commit_metrics.group_by do |metric|
        metric.timestamp.strftime("%Y-%m-%d")
      end

      # Sort by date and format for output
      daily_activity = daily_metrics.map do |date_str, metrics|
        {
          date: date_str,
          count: metrics.sum(&:value)
        }
      end.sort_by { |item| item[:date] }

      # Count days with at least one commit
      days_with_commits = daily_metrics.keys.size

      # Calculate commits per day and commit frequency
      commits_per_day = (total_commits.to_f / time_period).round(2)
      commit_frequency = (days_with_commits.to_f / time_period).round(2)

      # Construct the result
      result = {
        total_commits: total_commits,
        days_with_commits: days_with_commits,
        days_analyzed: time_period,
        commits_per_day: commits_per_day,
        commit_frequency: commit_frequency,
        daily_activity: daily_activity
      }

      # Cache the result if caching is enabled
      cache_result(repository, time_period, result) if @cache_port

      result
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

    # Retrieve cached result if available
    # @param repository [String, nil] Repository to filter by
    # @param time_period [Integer] Time period in days
    # @return [Hash, nil] Cached result or nil if not in cache
    def from_cache(repository, time_period)
      key = cache_key(repository, time_period)
      cached = @cache_port.read(key)
      return nil unless cached

      # Parse JSON if stored as string, or return the object directly
      cached.is_a?(String) ? JSON.parse(cached, symbolize_names: true) : cached
    rescue JSON::ParserError
      nil
    end

    # Cache the result
    # @param repository [String, nil] Repository that was filtered
    # @param time_period [Integer] Time period in days
    # @param result [Hash] Result to cache
    def cache_result(repository, time_period, result)
      key = cache_key(repository, time_period)
      @cache_port.write(key, result.to_json, expires_in: 1.hour)
    end
  end
end
