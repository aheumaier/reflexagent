# frozen_string_literal: true

module UseCases
  # DashboardMetrics is responsible for generating data for dashboard visualizations
  # It aggregates metrics and provides formatted data for charts and graphs
  class DashboardMetrics
    def initialize(storage_port:, cache_port:)
      @storage_port = storage_port
      @cache_port = cache_port
    end

    # Fetch commit metrics for dashboard visualization
    # @param repository [String] The repository to analyze
    # @param time_period [Integer] The number of days to look back
    # @param metrics [Array<String>] List of metrics to include (optional)
    # @return [Hash] Dashboard data structured for visualization
    def call(repository:, time_period: 30, metrics: nil)
      Rails.logger.debug { "DashboardMetrics.call for repository: #{repository}, period: #{time_period} days" }

      # Set time range
      since_date = time_period.days.ago

      # Try to get dashboard data from cache first
      cache_key = "dashboard:#{repository}:#{time_period}:#{metrics&.join('-') || 'all'}"
      cached_data = @cache_port.read(cache_key)

      return JSON.parse(cached_data) if cached_data

      # Default metrics if none specified
      metrics ||= [
        "commit_volume", "directory_hotspots", "file_extensions", "commit_types", "breaking_changes", "author_activity"
      ]

      # Build dashboard data object
      dashboard_data = {}

      # Only include requested metrics
      metrics.each do |metric|
        dashboard_data[metric.to_sym] = send("fetch_#{metric}_data", repository, since_date)
      end

      # Cache the results for 5 minutes
      @cache_port.write(cache_key, dashboard_data.to_json, ttl: 5.minutes)

      dashboard_data
    end

    private

    def fetch_commit_volume_data(repository, since_date)
      # Get commit activity by day
      activity = @storage_port.commit_activity_by_day(repository: repository, since: since_date)

      # Format for time series chart
      {
        chart_type: "time_series",
        title: "Commit Volume Over Time",
        data_points: activity.map do |day|
          {
            date: day[:date].strftime("%Y-%m-%d"),
            value: day[:commit_count]
          }
        end,
        summary: {
          total_commits: activity.sum { |day| day[:commit_count] },
          avg_per_day: (activity.sum { |day| day[:commit_count] }.to_f / activity.size).round(1)
        }
      }
    end

    def fetch_directory_hotspots_data(repository, since_date)
      # Get directory hotspots
      hotspots = @storage_port.hotspot_directories(repository: repository, since: since_date, limit: 10)

      # Format for treemap/heatmap visualization
      {
        chart_type: "treemap",
        title: "Directory Change Hotspots",
        data_points: hotspots.map do |dir|
          {
            name: dir[:directory],
            value: dir[:count],
            percentage: calculate_percentage(dir[:count], hotspots.sum { |d| d[:count] })
          }
        end,
        summary: {
          total_directories: hotspots.size,
          total_changes: hotspots.sum { |dir| dir[:count] }
        }
      }
    end

    def fetch_file_extensions_data(repository, since_date)
      # Get file extension hotspots
      extensions = @storage_port.hotspot_filetypes(repository: repository, since: since_date, limit: 10)

      # Format for pie chart visualization
      {
        chart_type: "pie",
        title: "File Type Distribution",
        data_points: extensions.map do |ext|
          {
            name: ext[:filetype],
            value: ext[:count],
            percentage: calculate_percentage(ext[:count], extensions.sum { |e| e[:count] })
          }
        end,
        summary: {
          total_extensions: extensions.size,
          top_extension: extensions.first&.dig(:filetype) || "none",
          top_extension_count: extensions.first&.dig(:count) || 0
        }
      }
    end

    def fetch_commit_types_data(repository, since_date)
      # Get commit type distribution
      types = @storage_port.commit_type_distribution(repository: repository, since: since_date)

      # Format for bar chart visualization
      {
        chart_type: "bar",
        title: "Commit Types",
        data_points: types.map do |type|
          {
            name: type[:type],
            value: type[:count],
            percentage: calculate_percentage(type[:count], types.sum { |t| t[:count] })
          }
        end,
        summary: {
          total_conventional_commits: types.sum { |t| t[:count] },
          top_type: types.first&.dig(:type) || "none",
          top_type_count: types.first&.dig(:count) || 0
        }
      }
    end

    def fetch_breaking_changes_data(repository, since_date)
      # Get breaking changes
      breaking = @storage_port.breaking_changes_by_author(repository: repository, since: since_date)

      # Format for visualization
      {
        chart_type: "bar",
        title: "Breaking Changes by Author",
        data_points: breaking.map do |bc|
          {
            name: bc[:author],
            value: bc[:breaking_count]
          }
        end,
        summary: {
          total_breaking_changes: breaking.sum { |bc| bc[:breaking_count] },
          authors_with_breaking_changes: breaking.size
        }
      }
    end

    def fetch_author_activity_data(repository, since_date)
      # Get author activity
      authors = @storage_port.author_activity(repository: repository, since: since_date, limit: 15)

      # Get lines changed by each author
      lines = @storage_port.lines_changed_by_author(repository: repository, since: since_date)

      # Merge the data
      authors_with_lines = authors.map do |author|
        line_data = lines.find { |l| l[:author] == author[:author] }

        {
          name: author[:author],
          commit_count: author[:commit_count],
          lines_added: line_data ? line_data[:lines_added] : 0,
          lines_deleted: line_data ? line_data[:lines_deleted] : 0,
          lines_changed: line_data ? line_data[:lines_changed] : 0
        }
      end

      # Format for visualization
      {
        chart_type: "stacked_bar",
        title: "Author Activity",
        data_points: authors_with_lines,
        summary: {
          total_authors: authors.size,
          total_commits: authors.sum { |a| a[:commit_count] },
          total_lines_changed: lines.sum { |l| l[:lines_changed] }
        }
      }
    end

    # Helper methods

    def calculate_percentage(count, total)
      total > 0 ? ((count.to_f / total) * 100).round(1) : 0
    end
  end
end
