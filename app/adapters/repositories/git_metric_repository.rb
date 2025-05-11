# frozen_string_literal: true

module Repositories
  # GitMetricRepository provides specialized methods for git-related metrics
  # that work across different git source systems (GitHub, Bitbucket, GitLab, etc.)
  class GitMetricRepository < BaseMetricRepository
    # Find hotspot directories for the given time period
    # @param since [Time] The start time for analysis
    # @param source [String, nil] Optional source system filter (github, bitbucket, etc.)
    # @param repository [String, nil] Optional repository filter
    # @param limit [Integer] Maximum number of results to return
    # @return [Array<Hash>] Array of directory hotspots with counts
    def hotspot_directories(since:, source: nil, repository: nil, limit: 10)
      context = { since: since, source: source, repository: repository, limit: limit }

      begin
        base_query = build_base_query(since: since, source: source, repository: repository)

        # Get hotspot directories using the base query
        log_debug("Finding hotspot directories since #{since}")

        hotspots = base_query.hotspot_directories(since: since, limit: limit)

        # Format the results as hashes
        hotspots.map do |hotspot|
          {
            directory: hotspot.directory,
            count: hotspot.change_count
          }
        end
      rescue StandardError => e
        handle_query_error("hotspot_directories", e, context)
      end
    end

    # Find hotspot file types for the given time period
    # @param since [Time] The start time for analysis
    # @param source [String, nil] Optional source system filter (github, bitbucket, etc.)
    # @param repository [String, nil] Optional repository filter
    # @param limit [Integer] Maximum number of results to return
    # @return [Array<Hash>] Array of file type hotspots with counts
    def hotspot_filetypes(since:, source: nil, repository: nil, limit: 10)
      context = { since: since, source: source, repository: repository, limit: limit }

      begin
        base_query = build_base_query(since: since, source: source, repository: repository)

        log_debug("Finding hotspot filetypes since #{since}")

        # Get hotspot file types using the base query
        hotspots = base_query.hotspot_files_by_extension(since: since, limit: limit)

        # Format the results as hashes
        hotspots.map do |hotspot|
          {
            filetype: hotspot.filetype,
            count: hotspot.change_count
          }
        end
      rescue StandardError => e
        handle_query_error("hotspot_filetypes", e, context)
      end
    end

    # Find distribution of commit types for the given time period
    # @param since [Time] The start time for analysis
    # @param source [String, nil] Optional source system filter (github, bitbucket, etc.)
    # @param repository [String, nil] Optional repository filter
    # @return [Array<Hash>] Array of commit types with counts
    def commit_type_distribution(since:, source: nil, repository: nil)
      context = { since: since, source: source, repository: repository }

      begin
        base_query = build_base_query(since: since, source: source, repository: repository)

        log_debug("Finding commit type distribution since #{since}")

        # Get commit type distribution using the base query
        distribution = base_query.commit_type_distribution(since: since)

        # Format the results as hashes
        distribution.map do |type|
          {
            type: type.commit_type,
            count: type.count
          }
        end
      rescue StandardError => e
        handle_query_error("commit_type_distribution", e, context)
      end
    end

    # Find most active authors for the given time period
    # @param since [Time] The start time for analysis
    # @param source [String, nil] Optional source system filter (github, bitbucket, etc.)
    # @param repository [String, nil] Optional repository filter
    # @param limit [Integer] Maximum number of results to return
    # @return [Array<Hash>] Array of authors with commit counts
    def author_activity(since:, source: nil, repository: nil, limit: 10)
      context = { since: since, source: source, repository: repository, limit: limit }

      begin
        base_query = build_base_query(since: since, source: source, repository: repository)

        log_debug("Finding author activity since #{since}")

        # Get author activity using the base query
        authors = base_query.author_activity(since: since, limit: limit)

        # Format the results as hashes
        authors.map do |author|
          {
            author: author.author,
            commit_count: author.commit_count
          }
        end
      rescue StandardError => e
        handle_query_error("author_activity", e, context)
      end
    end

    # Find lines changed by author for the given time period
    # @param since [Time] The start time for analysis
    # @param source [String, nil] Optional source system filter (github, bitbucket, etc.)
    # @param repository [String, nil] Optional repository filter
    # @return [Array<Hash>] Array of authors with lines added/removed
    def lines_changed_by_author(since:, source: nil, repository: nil)
      context = { since: since, source: source, repository: repository }

      begin
        base_query = build_base_query(since: since, source: source, repository: repository)

        log_debug("Finding lines changed by author since #{since}")

        # Get lines changed by author using the base query
        authors = base_query.lines_changed_by_author(since: since)

        # Format the results as hashes
        authors.map do |author|
          {
            author: author.author,
            lines_added: author.lines_added.to_i,
            lines_deleted: author.lines_deleted.to_i,
            lines_changed: author.lines_added.to_i + author.lines_deleted.to_i
          }
        end
      rescue StandardError => e
        handle_query_error("lines_changed_by_author", e, context)
      end
    end

    # Find breaking changes by author for the given time period
    # @param since [Time] The start time for analysis
    # @param source [String, nil] Optional source system filter (github, bitbucket, etc.)
    # @param repository [String, nil] Optional repository filter
    # @return [Array<Hash>] Array of authors with breaking change counts
    def breaking_changes_by_author(since:, source: nil, repository: nil)
      context = { since: since, source: source, repository: repository }

      begin
        base_query = build_base_query(since: since, source: source, repository: repository)

        log_debug("Finding breaking changes by author since #{since}")

        # Get breaking changes by author using the base query
        authors = base_query.breaking_changes_by_author(since: since)

        # Format the results as hashes
        authors.map do |author|
          {
            author: author.author,
            breaking_count: author.breaking_count
          }
        end
      rescue StandardError => e
        handle_query_error("breaking_changes_by_author", e, context)
      end
    end

    # Find commit activity by day for the given time period
    # @param since [Time] The start time for analysis
    # @param source [String, nil] Optional source system filter (github, bitbucket, etc.)
    # @param repository [String, nil] Optional repository filter
    # @return [Array<Hash>] Array of days with commit counts
    def commit_activity_by_day(since:, source: nil, repository: nil)
      context = { since: since, source: source, repository: repository }

      begin
        base_query = build_base_query(since: since, source: source, repository: repository)

        log_debug("Finding commit activity by day since #{since}")

        # Get commit activity by day using the base query
        activity = base_query.commit_activity_by_day(since: since)

        # Format the results as hashes
        activity.map do |day|
          {
            date: day.day,
            commit_count: day.commit_count
          }
        end
      rescue StandardError => e
        handle_query_error("commit_activity_by_day", e, context)
      end
    end

    # Get active repositories with optimized DB-level aggregation
    # @param start_time [Time] The start time for filtering activity
    # @param source [String, nil] Optional source system filter (github, bitbucket, etc.)
    # @param limit [Integer] Maximum number of repositories to return
    # @param page [Integer] Page number for pagination
    # @param per_page [Integer] Items per page for pagination
    # @return [Array<String>] List of repository names
    def get_active_repositories(start_time:, source: nil, limit: 50, page: nil, per_page: nil)
      context = { start_time: start_time, source: source, limit: limit, page: page, per_page: per_page }

      log_debug("Getting active repositories since #{start_time}")

      # Create a raw SQL query that efficiently aggregates repositories at the database level
      # Add source filtering for source-specific queries
      source_condition = source.present? ? "AND name LIKE '#{source}.%'" : ""

      # This avoids loading all metrics into memory
      sql = <<-SQL
        SELECT DISTINCT jsonb_extract_path_text(dimensions, 'repository') AS repository_name,
               COUNT(*) AS push_count
        FROM metrics
        WHERE name = 'github.push.total' #{source_condition}
          AND recorded_at >= ?
          AND dimensions @> '{"repository": {}}'::jsonb
        GROUP BY repository_name
        ORDER BY push_count DESC, repository_name ASC
      SQL

      # Apply pagination or limit
      if page && per_page
        offset = (page - 1) * per_page
        sql += " LIMIT ? OFFSET ?"
        params = [start_time, per_page, offset]
      else
        sql += " LIMIT ?"
        params = [start_time, limit]
      end

      # Execute the query directly for better performance
      begin
        result = ActiveRecord::Base.connection.exec_query(sql, "Get Active Repositories", params)

        # Extract repository names from the result
        result.map { |row| row["repository_name"] }.compact
      rescue StandardError => e
        # Log the error but do not raise - return empty array instead
        log_error("Error fetching active repositories: #{e.message}")
        log_error(e.backtrace.join("\n"))
        []
      end
    end

    protected

    # Build a base query that filters by source system if provided
    # @param since [Time] The start time for filtering
    # @param source [String, nil] Optional source system filter
    # @param repository [String, nil] Optional repository filter
    # @return [ActiveRecord::Relation] Base query with filters applied
    def build_base_query(since:, source: nil, repository: nil)
      context = { since: since, source: source, repository: repository }

      begin
        # Start with a base query filtered by time
        base_query = CommitMetric.since(since)

        # Apply source filter if provided (this will need implementation in CommitMetric)
        base_query = base_query.by_source(source) if source.present?

        # Apply repository filter if provided
        base_query = base_query.by_repository(repository) if repository.present?

        base_query
      rescue StandardError => e
        handle_query_error("build_base_query", e, context)
      end
    end

    private

    # Logging methods (delegate to the parent class's logging helpers)
    def log_debug(message)
      if @logger_port.respond_to?(:debug)
        @logger_port.debug { message }
      else
        @logger_port.debug(message)
      end
    end

    def log_error(message)
      if @logger_port.respond_to?(:error)
        @logger_port.error { message }
      else
        @logger_port.error(message)
      end
    end
  end
end
