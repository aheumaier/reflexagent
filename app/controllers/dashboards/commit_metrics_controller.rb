# frozen_string_literal: true

module Dashboards
  class CommitMetricsController < ApplicationController
    def index
      # Get time range from params with default of 30 days
      @days = (params[:days] || 30).to_i
      @since_date = @days.days.ago

      # Repository filter
      @repository = params[:repository]

      # Get commit metrics data using the metrics service directly
      # This approach avoids the dependency on dimension_extractor
      metrics_service = ServiceFactory.create_metrics_service

      # Get commit metrics data
      @commit_metrics = fetch_commit_metrics(@days, @repository)

      # Get list of repositories for filter dropdown
      begin
        @repositories = fetch_repositories(@days)
      rescue StandardError => e
        Rails.logger.error("Error fetching repositories list: #{e.message}")
        @repositories = []
      end

      # Log completion
      Rails.logger.info("Commit metrics data fetched successfully for #{@days} days period")
    end

    private

    # Method to fetch commit metrics data
    def fetch_commit_metrics(days = 30, repository = nil)
      metrics_service = ServiceFactory.create_metrics_service
      since_date = days.days.ago

      # If repository is provided, filter by that repository
      if repository.present?
        commit_analysis = {
          repository: repository
        }
      else
        # Get the top active repository if none specified
        top_repo = metrics_service.top_metrics("github.push.total", dimension: "repository", limit: 1,
                                                                    days: days).keys.first

        # Use the top repository or fallback to a default
        repository = top_repo || "unknown"
        commit_analysis = { repository: repository }
      end

      # Get directory hotspots
      begin
        commit_analysis[:directory_hotspots] = metrics_service.top_metrics(
          "github.push.directory_changes.daily",
          dimension: "directory",
          limit: 10,
          days: days
        ).map { |dir, count| { directory: dir, count: count, percentage: 0 } }
      rescue StandardError => e
        Rails.logger.error("Error fetching directory hotspots: #{e.message}")
        commit_analysis[:directory_hotspots] = []
      end

      # Get file extension hotspots
      begin
        commit_analysis[:file_extension_hotspots] = metrics_service.top_metrics(
          "github.push.filetype_changes.daily",
          dimension: "filetype",
          limit: 10,
          days: days
        ).map { |ext, count| { extension: ext, count: count, percentage: 0 } }
      rescue StandardError => e
        Rails.logger.error("Error fetching file extension hotspots: #{e.message}")
        commit_analysis[:file_extension_hotspots] = []
      end

      # Get commit types
      begin
        commit_analysis[:commit_types] = metrics_service.top_metrics(
          "github.push.commit_type.daily",
          dimension: "type",
          limit: 10,
          days: days
        ).map { |type, count| { type: type, count: count, percentage: 0 } }
      rescue StandardError => e
        Rails.logger.error("Error fetching commit types: #{e.message}")
        commit_analysis[:commit_types] = []
      end

      # Get author activity
      begin
        authors = metrics_service.top_metrics(
          "github.push.unique_authors",
          dimension: "author",
          limit: 10,
          days: days
        )

        # Get code additions by author
        additions_by_author = metrics_service.top_metrics(
          "github.push.code_additions.daily",
          dimension: "author",
          limit: 10,
          days: days
        )

        # Get code deletions by author
        deletions_by_author = metrics_service.top_metrics(
          "github.push.code_deletions.daily",
          dimension: "author",
          limit: 10,
          days: days
        )

        # Combine the data
        commit_analysis[:author_activity] = authors.map do |author, commit_count|
          lines_added = additions_by_author[author] || 0
          lines_deleted = deletions_by_author[author] || 0

          {
            author: author,
            commit_count: commit_count,
            lines_added: lines_added,
            lines_deleted: lines_deleted,
            lines_changed: lines_added + lines_deleted
          }
        end
      rescue StandardError => e
        Rails.logger.error("Error fetching author activity: #{e.message}")
        commit_analysis[:author_activity] = []
      end

      # Breaking changes
      begin
        breaking_changes = metrics_service.top_metrics(
          "github.push.breaking_change.daily",
          dimension: "author",
          limit: 10,
          days: days
        )

        commit_analysis[:breaking_changes] = {
          total: breaking_changes.values.sum,
          by_author: breaking_changes.map { |author, count| { author: author, count: count } }
        }
      rescue StandardError => e
        Rails.logger.error("Error fetching breaking changes: #{e.message}")
        commit_analysis[:breaking_changes] = { total: 0, by_author: [] }
      end

      # Commit volume
      begin
        daily_activity = metrics_service.aggregate_metrics("github.push.commits.daily", "daily", days)
        commit_analysis[:commit_volume] = {
          total_commits: daily_activity.values.sum,
          days_with_commits: daily_activity.values.count { |v| v > 0 },
          days_analyzed: days,
          commits_per_day: (daily_activity.values.sum.to_f / days).round(2),
          commit_frequency: (daily_activity.values.count { |v| v > 0 }.to_f / days).round(2),
          daily_activity: daily_activity.map { |date, count| { date: Date.parse(date), commit_count: count } }
        }
      rescue StandardError => e
        Rails.logger.error("Error fetching commit volume: #{e.message}")
        commit_analysis[:commit_volume] = {
          total_commits: 0,
          days_with_commits: 0,
          days_analyzed: days,
          commits_per_day: 0,
          commit_frequency: 0,
          daily_activity: []
        }
      end

      # Code churn
      begin
        additions = metrics_service.aggregate(
          "github.push.code_additions.daily",
          days: days,
          aggregation: "sum"
        ) || 0

        deletions = metrics_service.aggregate(
          "github.push.code_deletions.daily",
          days: days,
          aggregation: "sum"
        ) || 0

        total_churn = additions + deletions
        churn_ratio = deletions > 0 ? (additions.to_f / deletions).round(2) : 0

        commit_analysis[:code_churn] = {
          additions: additions,
          deletions: deletions,
          total_churn: total_churn,
          churn_ratio: churn_ratio
        }
      rescue StandardError => e
        Rails.logger.error("Error fetching code churn: #{e.message}")
        commit_analysis[:code_churn] = {
          additions: 0,
          deletions: 0,
          total_churn: 0,
          churn_ratio: 0
        }
      end

      commit_analysis
    end

    # Get list of repositories for filter dropdown
    def fetch_repositories(days = 30)
      metrics_service = ServiceFactory.create_metrics_service

      # Get active repositories sorted by activity
      repos = metrics_service.top_metrics(
        "github.push.total",
        dimension: "repository",
        limit: 50, # Get a reasonable number of repositories
        days: days
      ).keys

      # Return sorted list
      repos.sort
    end
  end
end
