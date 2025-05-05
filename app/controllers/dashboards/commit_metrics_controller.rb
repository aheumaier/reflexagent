# frozen_string_literal: true

module Dashboards
  class CommitMetricsController < ApplicationController
    def index
      # Filter by date range
      @period = params[:period] || "month"

      @start_date = case @period
                    when "week"
                      1.week.ago
                    when "month"
                      1.month.ago
                    when "quarter"
                      3.months.ago
                    when "year"
                      1.year.ago
                    else
                      1.month.ago
                    end

      # Repository filter
      @repository = params[:repository]
      base_query = CommitMetric.since(@start_date)
      base_query = base_query.by_repository(@repository) if @repository.present?

      # Get metrics
      @hotspot_directories = base_query.hotspot_directories(since: @start_date)
      @hotspot_filetypes = base_query.hotspot_files_by_extension(since: @start_date)
      @commit_types = base_query.commit_type_distribution(since: @start_date)
      @top_authors = base_query.author_activity(since: @start_date)
      @lines_by_author = base_query.lines_changed_by_author(since: @start_date)
      @breaking_changes = base_query.breaking_changes_by_author(since: @start_date)
      @daily_activity = base_query.commit_activity_by_day(since: @start_date)

      # List of repositories for the filter dropdown
      @repositories = CommitMetric.distinct.pluck(:repository).compact.sort
    end
  end
end
