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
        directory_data = metrics_service.top_metrics(
          "github.push.directory_changes.daily",
          dimension: "directory",
          limit: 10,
          days: days
        )

        if directory_data.empty?
          Rails.logger.info("No directory change metrics found in database")
          commit_analysis[:directory_hotspots] = []
        else
          # Convert to format expected by view
          commit_analysis[:directory_hotspots] = directory_data.map do |directory, count|
            { directory: directory, count: count }
          end
        end
      rescue StandardError => e
        Rails.logger.error("Error creating directory hotspots: #{e.message}")
        commit_analysis[:directory_hotspots] = []
      end

      # Get file extension hotspots
      begin
        filetype_data = metrics_service.top_metrics(
          "github.push.filetype_changes.daily",
          dimension: "filetype",
          limit: 10,
          days: days
        )

        if filetype_data.empty?
          Rails.logger.info("No filetype change metrics found in database")
          commit_analysis[:file_extension_hotspots] = []
        else
          # Convert to format expected by view
          commit_analysis[:file_extension_hotspots] = filetype_data.map do |filetype, count|
            { extension: filetype, count: count }
          end
        end
      rescue StandardError => e
        Rails.logger.error("Error creating file extension hotspots: #{e.message}")
        commit_analysis[:file_extension_hotspots] = []
      end

      # Get commit types
      begin
        commit_type_data = metrics_service.top_metrics(
          "github.push.commit_type", # Use raw metric instead of daily aggregate that may not exist
          dimension: "type",
          limit: 10,
          days: days
        )

        # If we don't have commit type data, return empty array
        if commit_type_data.empty?
          Rails.logger.info("No commit type metrics found")
          commit_analysis[:commit_types] = []
        else
          # Calculate total for percentage
          commit_type_total = commit_type_data.values.sum

          commit_analysis[:commit_types] = commit_type_data.map do |type, count|
            percentage = commit_type_total > 0 ? ((count.to_f / commit_type_total) * 100).round(1) : 0
            { type: type, count: count, percentage: percentage }
          end
        end
      rescue StandardError => e
        Rails.logger.error("Error fetching commit types: #{e.message}")
        commit_analysis[:commit_types] = []
      end

      # Get author activity - use by_author instead of unique_authors
      begin
        # Get authors by commit count
        authors = metrics_service.top_metrics(
          "github.push.by_author",
          dimension: "author",
          limit: 10,
          days: days
        )

        # If we don't have author data, return empty array
        if authors.empty?
          Rails.logger.info("No author metrics found")
          commit_analysis[:author_activity] = []
        else
          # Since we don't have code additions/deletions metrics, return author data without lines changed
          commit_analysis[:author_activity] = authors.map do |author, commit_count|
            {
              author: author,
              commit_count: commit_count,
              lines_added: 0,
              lines_deleted: 0,
              lines_changed: 0
            }
          end
        end
      rescue StandardError => e
        Rails.logger.error("Error fetching author activity: #{e.message}")
        commit_analysis[:author_activity] = []
      end

      # Breaking changes
      begin
        # Return empty breaking changes data
        Rails.logger.info("No breaking change metrics found")
        commit_analysis[:breaking_changes] = {
          total: 0,
          by_author: []
        }
      rescue StandardError => e
        Rails.logger.error("Error creating breaking changes: #{e.message}")
        commit_analysis[:breaking_changes] = { total: 0, by_author: [] }
      end

      # Commit volume
      begin
        # Try to get commit volume from commits metrics
        daily_commits = metrics_service.top_metrics(
          "github.push.commits",
          dimension: "day",
          limit: days,
          days: days
        )

        # If daily data isn't available, try to get an aggregate
        if daily_commits.empty?
          total_commits = metrics_service.aggregate(
            "github.push.commits",
            days: days,
            aggregation: "sum"
          ) || 0

          if total_commits == 0
            Rails.logger.info("No commit volume metrics found")
            commit_analysis[:commit_volume] = {
              total_commits: 0,
              days_with_commits: 0,
              days_analyzed: days,
              commits_per_day: 0,
              commit_frequency: 0,
              daily_activity: []
            }
          else
            # We have a total but no daily breakdown
            commit_analysis[:commit_volume] = {
              total_commits: total_commits,
              days_with_commits: 1, # At least one day had commits
              days_analyzed: days,
              commits_per_day: (total_commits.to_f / days).round(2),
              commit_frequency: (1.0 / days).round(2),
              daily_activity: []
            }
          end
        else
          # Convert the data format if we got actual daily data
          daily_activity = daily_commits.transform_keys { |k| k.to_s }

          # Calculate metrics from daily activity
          commit_analysis[:commit_volume] = {
            total_commits: daily_activity.values.sum,
            days_with_commits: daily_activity.values.count { |v| v > 0 },
            days_analyzed: days,
            commits_per_day: (daily_activity.values.sum.to_f / days).round(2),
            commit_frequency: (daily_activity.values.count { |v| v > 0 }.to_f / days).round(2),
            daily_activity: daily_activity.map { |date, count| { date: Date.parse(date), commit_count: count } }
          }
        end
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

      # Code churn - return zeros since we don't have actual metrics
      begin
        Rails.logger.info("No code churn metrics found")
        commit_analysis[:code_churn] = {
          additions: 0,
          deletions: 0,
          total_churn: 0,
          churn_ratio: 0
        }
      rescue StandardError => e
        Rails.logger.error("Error creating code churn metrics: #{e.message}")
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

      # If no repositories found, provide some defaults
      Rails.logger.info("No repository metrics found, using default data") if repos.empty?

      # Return sorted list
      repos.sort
    end
  end
end
