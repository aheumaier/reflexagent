# frozen_string_literal: true

module UseCases
  # AnalyzeCommits is responsible for analyzing commit patterns and detecting trends
  # It examines commit history for hotspots, breaking changes, and other patterns
  class AnalyzeCommits
    def initialize(storage_port:, cache_port:, dimension_extractor:)
      @storage_port = storage_port
      @cache_port = cache_port
      @dimension_extractor = dimension_extractor
    end

    # Analyze commits for a repository within a time period
    # @param repository [String] The repository name to analyze
    # @param since [DateTime] The start date for analysis
    # @param until_date [DateTime] The end date for analysis (optional)
    # @return [Hash] Analysis results with various metrics
    def call(repository:, since:, until_date: nil)
      Rails.logger.debug { "AnalyzeCommits.call for repository: #{repository}" }

      # Get commit metrics for the repository
      commit_metrics = fetch_commit_metrics(repository, since, until_date)

      # If we got a result directly from cache, it's already in the expected format
      return commit_metrics if commit_metrics.is_a?(Hash) && !commit_metrics.is_a?(Array)

      # Return empty results if no metrics found
      return empty_analysis_result if commit_metrics.empty?

      # Build and return the analysis result
      {
        directory_hotspots: analyze_directory_hotspots(commit_metrics),
        file_extension_hotspots: analyze_file_extensions(commit_metrics),
        commit_types: analyze_commit_types(commit_metrics),
        breaking_changes: analyze_breaking_changes(commit_metrics),
        author_activity: analyze_author_activity(commit_metrics),
        commit_volume: analyze_commit_volume(commit_metrics),
        code_churn: analyze_code_churn(commit_metrics)
      }
    end

    private

    def fetch_commit_metrics(repository, since, until_date)
      filters = {
        repository: repository,
        since: since
      }
      filters[:until] = until_date if until_date

      # Try to get from cache first
      cache_key = "commit_metrics:#{repository}:#{since.to_i}:#{until_date&.to_i || 'now'}"
      cached_metrics = @cache_port.read(cache_key)

      # If we have cached data, return it without modification
      # The JSON.parse will return a hash with string keys
      return JSON.parse(cached_metrics) if cached_metrics

      # Fetch from storage if not in cache
      metrics = @storage_port.list_metrics(filters)

      # Cache the results for 5 minutes
      @cache_port.write(cache_key, metrics.to_json, ttl: 5.minutes)

      metrics
    end

    def analyze_directory_hotspots(commit_metrics)
      # Get directory hotspots from the storage port
      hotspots = @storage_port.hotspot_directories(
        repository: extract_repository(commit_metrics),
        since: extract_earliest_date(commit_metrics),
        limit: 10
      )

      hotspots.map do |hotspot|
        {
          directory: hotspot[:directory],
          count: hotspot[:count],
          percentage: calculate_percentage(hotspot[:count], total_directory_changes(hotspots))
        }
      end
    end

    def analyze_file_extensions(commit_metrics)
      # Get file extension hotspots from the storage port
      hotspots = @storage_port.hotspot_filetypes(
        repository: extract_repository(commit_metrics),
        since: extract_earliest_date(commit_metrics),
        limit: 10
      )

      hotspots.map do |hotspot|
        {
          extension: hotspot[:filetype],
          count: hotspot[:count],
          percentage: calculate_percentage(hotspot[:count], total_extension_changes(hotspots))
        }
      end
    end

    def analyze_commit_types(commit_metrics)
      # Get commit type distribution from the storage port
      types = @storage_port.commit_type_distribution(
        repository: extract_repository(commit_metrics),
        since: extract_earliest_date(commit_metrics)
      )

      types.map do |type|
        {
          type: type[:type],
          count: type[:count],
          percentage: calculate_percentage(type[:count], total_commit_types(types))
        }
      end
    end

    def analyze_breaking_changes(commit_metrics)
      # Get breaking changes by author from the storage port
      breaking_changes = @storage_port.breaking_changes_by_author(
        repository: extract_repository(commit_metrics),
        since: extract_earliest_date(commit_metrics)
      )

      # Format the results
      {
        total: breaking_changes.sum { |bc| bc[:breaking_count] },
        by_author: breaking_changes.map do |bc|
          {
            author: bc[:author],
            count: bc[:breaking_count]
          }
        end
      }
    end

    def analyze_author_activity(commit_metrics)
      # Get commit activity by author from the storage port
      authors = @storage_port.author_activity(
        repository: extract_repository(commit_metrics),
        since: extract_earliest_date(commit_metrics),
        limit: 10
      )

      # Get lines changed by author
      lines_by_author = @storage_port.lines_changed_by_author(
        repository: extract_repository(commit_metrics),
        since: extract_earliest_date(commit_metrics)
      )

      # Merge the data
      authors.map do |author|
        lines_data = lines_by_author.find { |a| a[:author] == author[:author] } ||
                     { lines_added: 0, lines_deleted: 0, lines_changed: 0 }

        {
          author: author[:author],
          commit_count: author[:commit_count],
          lines_added: lines_data[:lines_added],
          lines_deleted: lines_data[:lines_deleted],
          lines_changed: lines_data[:lines_changed]
        }
      end
    end

    def analyze_commit_volume(commit_metrics)
      # Get commit activity by day from the storage port
      activity = @storage_port.commit_activity_by_day(
        repository: extract_repository(commit_metrics),
        since: extract_earliest_date(commit_metrics)
      )

      # Calculate statistics
      commits = activity.sum { |day| day[:commit_count] }
      days_with_commits = activity.count { |day| day[:commit_count] > 0 }
      days_total = [(activity.last[:date] - activity.first[:date]).to_i + 1, 1].max

      {
        total_commits: commits,
        days_with_commits: days_with_commits,
        days_analyzed: days_total,
        commits_per_day: (commits.to_f / days_total).round(2),
        commit_frequency: (days_with_commits.to_f / days_total).round(2),
        daily_activity: activity
      }
    end

    def analyze_code_churn(commit_metrics)
      # Initialize totals
      total_additions = 0
      total_deletions = 0

      # Process each metric to extract additions and deletions
      commit_metrics.each do |metric|
        # Check if this is a hash or object metric
        if metric.is_a?(Hash)
          # For hash-style metrics
          if metric[:name] =~ /code_additions|files_added/
            total_additions += metric[:value].to_i
          elsif metric[:name] =~ /code_deletions|files_removed/
            total_deletions += metric[:value].to_i
          end
        elsif metric.respond_to?(:name) && metric.respond_to?(:value)
          # For object-style metrics
          if metric.name =~ /code_additions|files_added/
            total_additions += metric.value.to_i
          elsif metric.name =~ /code_deletions|files_removed/
            total_deletions += metric.value.to_i
          end
        end
      end

      total_churn = total_additions + total_deletions

      {
        additions: total_additions,
        deletions: total_deletions,
        total_churn: total_churn,
        churn_ratio: total_deletions > 0 ? (total_additions.to_f / total_deletions).round(2) : total_additions
      }
    end

    # Helper methods

    def empty_analysis_result
      {
        directory_hotspots: [],
        file_extension_hotspots: [],
        commit_types: [],
        breaking_changes: { total: 0, by_author: [] },
        author_activity: [],
        commit_volume: {
          total_commits: 0,
          days_with_commits: 0,
          days_analyzed: 0,
          commits_per_day: 0,
          commit_frequency: 0,
          daily_activity: []
        },
        code_churn: {
          additions: 0,
          deletions: 0,
          total_churn: 0,
          churn_ratio: 0
        }
      }
    end

    def extract_repository(commit_metrics)
      # Extract repository from the first metric
      first_metric = commit_metrics.first
      return "unknown" unless first_metric

      # Handle both hash and object forms of metrics
      if first_metric.is_a?(Hash) && first_metric[:dimensions] && first_metric[:dimensions][:repository]
        return first_metric[:dimensions][:repository]
      elsif first_metric.respond_to?(:dimensions) && first_metric.dimensions[:repository]
        return first_metric.dimensions[:repository]
      end

      "unknown"
    end

    def extract_earliest_date(commit_metrics)
      # Find the earliest date in the metrics
      return 30.days.ago if commit_metrics.empty?

      earliest_time = nil

      commit_metrics.each do |metric|
        time = if metric.is_a?(Hash) && metric[:timestamp]
                 metric[:timestamp]
               elsif metric.respond_to?(:timestamp)
                 metric.timestamp
               end

        earliest_time = time if time && (earliest_time.nil? || time < earliest_time)
      end

      earliest_time || 30.days.ago
    end

    def calculate_percentage(count, total)
      total > 0 ? ((count.to_f / total) * 100).round(1) : 0
    end

    def total_directory_changes(hotspots)
      hotspots.sum { |h| h[:count] }
    end

    def total_extension_changes(hotspots)
      hotspots.sum { |h| h[:count] }
    end

    def total_commit_types(types)
      types.sum { |t| t[:count] }
    end
  end
end
