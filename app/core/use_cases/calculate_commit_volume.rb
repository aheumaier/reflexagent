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
    def call(time_period: 30, repository: nil)
      # Try to get from cache first
      cache_key = "commit_volume:#{repository || 'all'}:days_#{time_period}"
      cached = @cache_port.read(cache_key)

      return JSON.parse(cached, symbolize_names: true) if cached

      start_time = time_period.days.ago

      # Get all commit metrics for the time period
      commit_metrics = @storage_port.list_metrics(
        name: "github.push.commits.total",
        start_time: start_time
      )

      # Filter metrics by repository if provided
      if repository
        commit_metrics = commit_metrics.select do |metric|
          metric.dimensions["repository"] == repository
        end
      end

      # If there are no metrics, return zeros
      if commit_metrics.empty?
        result = {
          total_commits: 0,
          days_with_commits: 0,
          days_analyzed: time_period,
          commits_per_day: 0,
          commit_frequency: 0,
          daily_activity: []
        }

        @cache_port.write(cache_key, result.to_json, expires_in: 1.hour)
        return result
      end

      # Calculate total commits
      total_commits = commit_metrics.sum(&:value)

      # Group metrics by day using date portion only (without time)
      # This ensures metrics from the same day but different times are grouped together
      daily_metrics = {}

      # Group by date string (YYYY-MM-DD) ignoring the time portion
      commit_metrics.group_by do |metric|
        # Handle the case where the metric timestamp might be a string or a Time object
        timestamp = metric.timestamp
        date_str = if timestamp.is_a?(String)
                     # If it's a string, parse it first
                     Time.parse(timestamp).to_date.strftime("%Y-%m-%d")
                   else
                     # If it's already a Time object, just get the date portion
                     timestamp.to_date.strftime("%Y-%m-%d")
                   end
      end.each do |date_str, day_metrics|
        # Sum the values for all metrics on this date
        daily_metrics[date_str] = day_metrics.sum(&:value)
      end

      # Count days with at least one commit
      days_with_commits = daily_metrics.keys.size

      # Format daily activity for output
      daily_activity = daily_metrics.map do |date_str, count|
        {
          date: date_str,
          count: count
        }
      end.sort_by { |item| item[:date] }

      # Calculate commits per day and commit frequency
      commits_per_day = (total_commits.to_f / time_period).round(2)
      commit_frequency = (days_with_commits.to_f / time_period).round(2)

      # Build the result
      result = {
        total_commits: total_commits,
        days_with_commits: days_with_commits,
        days_analyzed: time_period,
        commits_per_day: commits_per_day,
        commit_frequency: commit_frequency,
        daily_activity: daily_activity
      }

      # Cache the result
      @cache_port.write(cache_key, result.to_json, expires_in: 1.hour)

      result
    end
  end
end
