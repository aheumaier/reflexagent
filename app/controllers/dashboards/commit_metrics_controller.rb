# frozen_string_literal: true

module Dashboards
  class CommitMetricsController < ApplicationController
    def index
      # Get time range from params with default of 30 days
      @days = (params[:days] || 30).to_i
      @since_date = @days.days.ago

      # Repository filter
      @repository = params[:repository]

      # Get commit metrics data using dashboard_adapter
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
      # Use dashboard_adapter from ApplicationController
      time_period = days

      # If repository is provided, filter by that repository
      if repository.present?
        # Get repository commit analysis from dashboard_adapter
        dashboard_adapter.get_repository_commit_analysis(
          repository: repository,
          time_period: time_period
        )
      else
        # Get the top active repository if none specified
        repositories = dashboard_adapter.get_available_repositories(time_period: time_period, limit: 1)

        # Use the top repository or fallback to a default
        repository = repositories.first || "unknown"

        # Get repository commit analysis from dashboard_adapter
        dashboard_adapter.get_repository_commit_analysis(
          repository: repository,
          time_period: time_period
        )
      end
    end

    # Get list of repositories for filter dropdown
    def fetch_repositories(days = 30)
      # Use dashboard_adapter to get repositories
      repositories = dashboard_adapter.get_available_repositories(
        time_period: days,
        limit: 50 # Get a reasonable number of repositories
      )

      # If no repositories found, log it
      Rails.logger.info("No repository metrics found, using default data") if repositories.empty?

      # Return sorted list
      repositories.sort
    end
  end
end
