# frozen_string_literal: true

module Repositories
  # IssueMetricRepository provides specialized methods for issue-related metrics
  # that work across different issue tracking systems (GitHub, Jira, GitLab, etc.)
  class IssueMetricRepository < BaseMetricRepository
    # Find issue resolution time statistics
    # @param since [Time] The start time for analysis
    # @param source [String, nil] Optional source system filter (github, jira, etc.)
    # @param project [String, nil] Optional project/repository filter
    # @return [Hash] Resolution time statistics (average, median, p90)
    def resolution_time_stats(since:, source: nil, project: nil)
      context = { since: since, source: source, project: project }

      begin
        log_debug("Finding issue resolution time statistics since #{since}")

        # Build the base query with filters
        dimensions = {}
        dimensions[:repository] = project if project

        # Find resolution time metrics across different sources
        resolution_times = []

        # GitHub issues
        if source.nil? || source.downcase == "github"
          github_metrics = find_metrics_by_name_and_dimensions(
            "github.issue.time_to_close",
            dimensions,
            since
          )
          resolution_times.concat(github_metrics)
        end

        # Jira issues
        if source.nil? || source.downcase == "jira"
          dimensions[:project] = project if project # Jira uses 'project' instead of 'repository'
          jira_metrics = find_metrics_by_name_and_dimensions(
            "jira.issue.time_to_close",
            dimensions,
            since
          )
          resolution_times.concat(jira_metrics)
        end

        # Calculate statistics
        if resolution_times.empty?
          return {
            issue_count: 0,
            average_hours: 0,
            median_hours: 0,
            p90_hours: 0
          }
        end

        # Extract values (assuming they're in hours)
        values = resolution_times.map(&:value)

        # Calculate average
        average = values.sum / values.size

        # Calculate median
        sorted_values = values.sort
        median = if values.size.odd?
                   sorted_values[values.size / 2]
                 else
                   (sorted_values[(values.size / 2) - 1] + sorted_values[values.size / 2]) / 2.0
                 end

        # Calculate p90
        p90_index = (values.size * 0.9).ceil - 1
        p90 = sorted_values[p90_index]

        {
          issue_count: resolution_times.size,
          average_hours: average.round(2),
          median_hours: median.round(2),
          p90_hours: p90.round(2)
        }
      rescue StandardError => e
        handle_query_error("resolution_time_stats", e, context)
      end
    end

    # Find issue creation rates
    # @param since [Time] The start time for analysis
    # @param until_time [Time, nil] Optional end time for analysis
    # @param source [String, nil] Optional source system filter (github, jira, etc.)
    # @param project [String, nil] Optional project/repository filter
    # @param interval [String] Time interval for grouping ('day', 'week', 'month')
    # @return [Array<Hash>] Issue creation counts grouped by interval
    def issue_creation_rates(since:, until_time: nil, source: nil, project: nil, interval: "week")
      context = {
        since: since,
        until_time: until_time,
        source: source,
        project: project,
        interval: interval
      }

      begin
        log_debug("Finding issue creation rates since #{since}")

        # Default end time to now if not provided
        until_time ||= Time.current

        # Convert interval string to seconds
        interval_seconds = case interval.downcase
                           when "day"
                             86_400 # 1 day
                           when "week"
                             604_800 # 1 week
                           when "month"
                             2_592_000 # 30 days
                           else
                             604_800 # default to 1 week
                           end

        # Build dimensions for filtering
        dimensions = {}
        dimensions[:repository] = project if project

        # Get all issue creation metrics
        creation_metrics = []

        # GitHub issues
        if source.nil? || source.downcase == "github"
          github_metrics = find_metrics_by_name_and_dimensions(
            "github.issue.created",
            dimensions,
            since
          ).select { |m| m.timestamp <= until_time }
          creation_metrics.concat(github_metrics)
        end

        # Jira issues
        if source.nil? || source.downcase == "jira"
          dimensions[:project] = project if project # Jira uses 'project' instead of 'repository'
          jira_metrics = find_metrics_by_name_and_dimensions(
            "jira.issue.created",
            dimensions,
            since
          ).select { |m| m.timestamp <= until_time }
          creation_metrics.concat(jira_metrics)
        end

        # Group metrics by time intervals
        grouped_metrics = {}

        # Calculate number of intervals
        total_seconds = until_time - since
        num_intervals = (total_seconds / interval_seconds).ceil

        # Initialize all intervals with zero
        num_intervals.times do |i|
          interval_start = since + (i * interval_seconds)
          interval_end = [interval_start + interval_seconds, until_time].min
          grouped_metrics[interval_start] = {
            start_time: interval_start,
            end_time: interval_end,
            count: 0,
            source_breakdown: {}
          }
        end

        # Fill in the counts for each interval
        creation_metrics.each do |metric|
          # Find which interval this metric belongs to
          interval_index = ((metric.timestamp - since) / interval_seconds).floor
          interval_start = since + (interval_index * interval_seconds)

          # Skip if outside our range (shouldn't happen, but just to be safe)
          next unless grouped_metrics[interval_start]

          # Increment total count
          grouped_metrics[interval_start][:count] += metric.value.to_i

          # Track counts by source
          source_key = metric.source.to_s
          grouped_metrics[interval_start][:source_breakdown][source_key] ||= 0
          grouped_metrics[interval_start][:source_breakdown][source_key] += metric.value.to_i
        end

        # Convert to array and sort by time
        grouped_metrics.values.sort_by { |m| m[:start_time] }
      rescue StandardError => e
        handle_query_error("issue_creation_rates", e, context)
      end
    end

    # Find issue close rates
    # @param since [Time] The start time for analysis
    # @param until_time [Time, nil] Optional end time for analysis
    # @param source [String, nil] Optional source system filter (github, jira, etc.)
    # @param project [String, nil] Optional project/repository filter
    # @param interval [String] Time interval for grouping ('day', 'week', 'month')
    # @return [Array<Hash>] Issue closure counts grouped by interval
    def issue_close_rates(since:, until_time: nil, source: nil, project: nil, interval: "week")
      context = {
        since: since,
        until_time: until_time,
        source: source,
        project: project,
        interval: interval
      }

      begin
        log_debug("Finding issue close rates since #{since}")

        # Default end time to now if not provided
        until_time ||= Time.current

        # Convert interval string to seconds
        interval_seconds = case interval.downcase
                           when "day"
                             86_400 # 1 day
                           when "week"
                             604_800 # 1 week
                           when "month"
                             2_592_000 # 30 days
                           else
                             604_800 # default to 1 week
                           end

        # Build dimensions for filtering
        dimensions = {}
        dimensions[:repository] = project if project

        # Get all issue closure metrics
        closure_metrics = []

        # GitHub issues
        if source.nil? || source.downcase == "github"
          github_metrics = find_metrics_by_name_and_dimensions(
            "github.issue.closed",
            dimensions,
            since
          ).select { |m| m.timestamp <= until_time }
          closure_metrics.concat(github_metrics)
        end

        # Jira issues
        if source.nil? || source.downcase == "jira"
          dimensions[:project] = project if project # Jira uses 'project' instead of 'repository'
          jira_metrics = find_metrics_by_name_and_dimensions(
            "jira.issue.closed",
            dimensions,
            since
          ).select { |m| m.timestamp <= until_time }
          closure_metrics.concat(jira_metrics)
        end

        # Group metrics by time intervals
        grouped_metrics = {}

        # Calculate number of intervals
        total_seconds = until_time - since
        num_intervals = (total_seconds / interval_seconds).ceil

        # Initialize all intervals with zero
        num_intervals.times do |i|
          interval_start = since + (i * interval_seconds)
          interval_end = [interval_start + interval_seconds, until_time].min
          grouped_metrics[interval_start] = {
            start_time: interval_start,
            end_time: interval_end,
            count: 0,
            source_breakdown: {}
          }
        end

        # Fill in the counts for each interval
        closure_metrics.each do |metric|
          # Find which interval this metric belongs to
          interval_index = ((metric.timestamp - since) / interval_seconds).floor
          interval_start = since + (interval_index * interval_seconds)

          # Skip if outside our range (shouldn't happen, but just to be safe)
          next unless grouped_metrics[interval_start]

          # Increment total count
          grouped_metrics[interval_start][:count] += metric.value.to_i

          # Track counts by source
          source_key = metric.source.to_s
          grouped_metrics[interval_start][:source_breakdown][source_key] ||= 0
          grouped_metrics[interval_start][:source_breakdown][source_key] += metric.value.to_i
        end

        # Convert to array and sort by time
        grouped_metrics.values.sort_by { |m| m[:start_time] }
      rescue StandardError => e
        handle_query_error("issue_close_rates", e, context)
      end
    end

    # Find issue backlog growth
    # @param since [Time] The start time for analysis
    # @param until_time [Time, nil] Optional end time for analysis
    # @param source [String, nil] Optional source system filter (github, jira, etc.)
    # @param project [String, nil] Optional project/repository filter
    # @param interval [String] Time interval for grouping ('day', 'week', 'month')
    # @return [Array<Hash>] Net backlog change grouped by interval
    def backlog_growth(since:, until_time: nil, source: nil, project: nil, interval: "week")
      context = {
        since: since,
        until_time: until_time,
        source: source,
        project: project,
        interval: interval
      }

      begin
        log_debug("Finding backlog growth since #{since}")

        # Get creation and closure data
        creations = issue_creation_rates(
          since: since,
          until_time: until_time,
          source: source,
          project: project,
          interval: interval
        )

        closures = issue_close_rates(
          since: since,
          until_time: until_time,
          source: source,
          project: project,
          interval: interval
        )

        # Combine the data to calculate net change
        result = []

        creations.each_with_index do |creation, index|
          closure = closures[index]

          # Calculate net change (positive means backlog growth, negative means reduction)
          net_change = creation[:count] - closure[:count]

          # Calculate source breakdown of net change
          source_breakdown = {}
          all_sources = (creation[:source_breakdown].keys + closure[:source_breakdown].keys).uniq

          all_sources.each do |source_key|
            created = creation[:source_breakdown][source_key] || 0
            closed = closure[:source_breakdown][source_key] || 0
            source_breakdown[source_key] = created - closed
          end

          result << {
            start_time: creation[:start_time],
            end_time: creation[:end_time],
            created: creation[:count],
            closed: closure[:count],
            net_change: net_change,
            source_breakdown: source_breakdown
          }
        end

        result
      rescue StandardError => e
        handle_query_error("backlog_growth", e, context)
      end
    end

    # Find issue assignee workload
    # @param since [Time] The start time for analysis
    # @param source [String, nil] Optional source system filter (github, jira, etc.)
    # @param project [String, nil] Optional project/repository filter
    # @param limit [Integer] Maximum number of assignees to return
    # @return [Array<Hash>] Assignees with their issue counts
    def assignee_workload(since:, source: nil, project: nil, limit: 10)
      context = { since: since, source: source, project: project, limit: limit }

      begin
        log_debug("Finding assignee workload since #{since}")

        # Build dimensions for filtering
        dimensions = {}
        dimensions[:repository] = project if project

        # Get currently open issues with assignees
        # This requires a different approach than just using metrics
        # We need to query the actual issue data

        # For now, we'll use a simpler approach with metrics
        # In a real implementation, this would need to be more sophisticated

        # Example GitHub query (simplified)
        assignee_metrics = []

        if source.nil? || source.downcase == "github"
          # Find all assignee metrics
          assignee_metrics = find_metrics_by_name_and_dimensions(
            "github.issue.assignee_count",
            dimensions,
            since
          )
        end

        # Group by assignee
        assignees = {}

        assignee_metrics.each do |metric|
          assignee = metric.dimensions["assignee"]
          next unless assignee

          assignees[assignee] ||= {
            assignee: assignee,
            issue_count: 0,
            source: metric.source
          }

          assignees[assignee][:issue_count] += metric.value.to_i
        end

        # Sort by issue count (descending) and limit results
        assignees.values
                 .sort_by { |a| -a[:issue_count] }
                 .take(limit)
      rescue StandardError => e
        handle_query_error("assignee_workload", e, context)
      end
    end

    # Find issue type distribution
    # @param since [Time] The start time for analysis
    # @param source [String, nil] Optional source system filter (github, jira, etc.)
    # @param project [String, nil] Optional project/repository filter
    # @return [Array<Hash>] Issue types with their counts
    def issue_type_distribution(since:, source: nil, project: nil)
      context = { since: since, source: source, project: project }

      begin
        log_debug("Finding issue type distribution since #{since}")

        # Build dimensions for filtering
        dimensions = {}
        dimensions[:repository] = project if project

        # Get all issue type metrics
        type_metrics = []

        # GitHub issues
        if source.nil? || source.downcase == "github"
          github_metrics = find_metrics_by_name_and_dimensions(
            "github.issue.type_distribution",
            dimensions,
            since
          )
          type_metrics.concat(github_metrics)
        end

        # Jira issues
        if source.nil? || source.downcase == "jira"
          dimensions[:project] = project if project
          jira_metrics = find_metrics_by_name_and_dimensions(
            "jira.issue.type_distribution",
            dimensions,
            since
          )
          type_metrics.concat(jira_metrics)
        end

        # Group by issue type
        types = {}

        type_metrics.each do |metric|
          issue_type = metric.dimensions["type"] || "unknown"

          types[issue_type] ||= {
            type: issue_type,
            count: 0,
            sources: {}
          }

          types[issue_type][:count] += metric.value.to_i

          # Track counts by source
          source_key = metric.source.to_s
          types[issue_type][:sources][source_key] ||= 0
          types[issue_type][:sources][source_key] += metric.value.to_i
        end

        # Sort by count (descending)
        types.values.sort_by { |t| -t[:count] }
      rescue StandardError => e
        handle_query_error("issue_type_distribution", e, context)
      end
    end

    # Find issue priority distribution
    # @param since [Time] The start time for analysis
    # @param source [String, nil] Optional source system filter (github, jira, etc.)
    # @param project [String, nil] Optional project/repository filter
    # @return [Array<Hash>] Issue priorities with their counts
    def issue_priority_distribution(since:, source: nil, project: nil)
      context = { since: since, source: source, project: project }

      begin
        log_debug("Finding issue priority distribution since #{since}")

        # Build dimensions for filtering
        dimensions = {}
        dimensions[:repository] = project if project

        # Get all issue priority metrics
        priority_metrics = []

        # GitHub issues
        if source.nil? || source.downcase == "github"
          github_metrics = find_metrics_by_name_and_dimensions(
            "github.issue.priority_distribution",
            dimensions,
            since
          )
          priority_metrics.concat(github_metrics)
        end

        # Jira issues
        if source.nil? || source.downcase == "jira"
          dimensions[:project] = project if project
          jira_metrics = find_metrics_by_name_and_dimensions(
            "jira.issue.priority_distribution",
            dimensions,
            since
          )
          priority_metrics.concat(jira_metrics)
        end

        # Group by priority
        priorities = {}

        # Define standard priority mapping for normalization
        priority_mapping = {
          # GitHub labels to standard priorities
          "priority:high" => "high",
          "priority:medium" => "medium",
          "priority:low" => "low",
          "bug" => "high", # Common GitHub convention

          # Jira priorities to standard priorities
          "highest" => "critical",
          "high" => "high",
          "medium" => "medium",
          "low" => "low",
          "lowest" => "trivial"
        }

        priority_metrics.each do |metric|
          raw_priority = metric.dimensions["priority"] || "unknown"

          # Normalize priority
          priority = priority_mapping[raw_priority.downcase] || raw_priority

          priorities[priority] ||= {
            priority: priority,
            count: 0,
            sources: {}
          }

          priorities[priority][:count] += metric.value.to_i

          # Track counts by source
          source_key = metric.source.to_s
          priorities[priority][:sources][source_key] ||= 0
          priorities[priority][:sources][source_key] += metric.value.to_i
        end

        # Define standard priority order for sorting
        priority_order = {
          "critical" => 0,
          "high" => 1,
          "medium" => 2,
          "low" => 3,
          "trivial" => 4
        }

        # Sort by priority (critical to trivial), then by count (descending) for priorities not in our order
        priorities.values.sort_by do |p|
          [priority_order[p[:priority]] || 999, -p[:count]]
        end
      rescue StandardError => e
        handle_query_error("issue_priority_distribution", e, context)
      end
    end

    # Find issue comment activity
    # @param since [Time] The start time for analysis
    # @param source [String, nil] Optional source system filter (github, jira, etc.)
    # @param project [String, nil] Optional project/repository filter
    # @param limit [Integer] Maximum number of issues to return
    # @return [Array<Hash>] Issues with their comment counts
    def issue_comment_activity(since:, source: nil, project: nil, limit: 10)
      context = { since: since, source: source, project: project, limit: limit }

      begin
        log_debug("Finding issue comment activity since #{since}")

        # Build dimensions for filtering
        dimensions = {}
        dimensions[:repository] = project if project

        # Get all comment metrics
        comment_metrics = []

        # GitHub comments
        if source.nil? || source.downcase == "github"
          github_metrics = find_metrics_by_name_and_dimensions(
            "github.issue.comment_count",
            dimensions,
            since
          )
          comment_metrics.concat(github_metrics)
        end

        # Jira comments
        if source.nil? || source.downcase == "jira"
          dimensions[:project] = project if project
          jira_metrics = find_metrics_by_name_and_dimensions(
            "jira.issue.comment_count",
            dimensions,
            since
          )
          comment_metrics.concat(jira_metrics)
        end

        # Group by issue
        issues = {}

        comment_metrics.each do |metric|
          issue_key = metric.dimensions["issue_id"] || metric.dimensions["issue_key"]
          next unless issue_key

          issues[issue_key] ||= {
            issue_id: issue_key,
            title: metric.dimensions["title"] || "Unknown Issue",
            comment_count: 0,
            source: metric.source,
            url: metric.dimensions["url"],
            last_updated: metric.timestamp
          }

          # Always set the comment count from the metric value
          issues[issue_key][:comment_count] = metric.value.to_i
          issues[issue_key][:last_updated] = metric.timestamp
        end

        # Sort by comment count (descending) and limit results
        issues.values
              .sort_by { |i| -i[:comment_count] }
              .take(limit)
      rescue StandardError => e
        handle_query_error("issue_comment_activity", e, context)
      end
    end

    protected

    # Build a base query that filters by source system and issue metrics
    # @param since [Time] The start time for filtering
    # @param source [String, nil] Optional source system filter
    # @param project [String, nil] Optional project/repository filter
    # @return [ActiveRecord::Relation] Base query with filters applied
    def build_issue_base_query(since:, source: nil, project: nil)
      context = { since: since, source: source, project: project }

      begin
        # Build a query for issue metrics
        query = DomainMetric.where("recorded_at >= ?", since)

        # Add source filter if provided
        query = if source
                  query.where("name LIKE ?", "#{source}.issue.%")
                else
                  query.where("name LIKE '%.issue.%'")
                end

        # Add project/repository filter if provided
        if project
          # We need to handle different sources differently
          # GitHub uses 'repository', Jira uses 'project'
          query = query.where(
            "dimensions @> ? OR dimensions @> ?",
            { repository: project }.to_json,
            { project: project }.to_json
          )
        end

        query
      rescue StandardError => e
        handle_query_error("build_issue_base_query", e, context)
      end
    end

    private

    # Logging methods
    def log_debug(message)
      if @logger_port.respond_to?(:debug)
        @logger_port.debug { message }
      else
        @logger_port.debug(message)
      end
    end
  end
end
