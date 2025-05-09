# frozen_string_literal: true

module UseCases
  # AnalyzeBuildPerformance tracks build success rates and durations
  class AnalyzeBuildPerformance
    def initialize(storage_port:, cache_port: nil, metric_naming_port: nil, logger_port: nil)
      @storage_port = storage_port
      @cache_port = cache_port
      @metric_naming_port = metric_naming_port || DependencyContainer.resolve(:metric_naming_port)
      @logger_port = logger_port || Rails.logger
    end

    # Analyze build performance metrics from workflow job and CI build data
    # @param time_period [Integer] The number of days to look back
    # @param repository [String, nil] Optional repository filter
    # @return [Hash] Build performance metrics
    def call(time_period:, repository: nil)
      if @cache_port && (cached_result = from_cache(time_period, repository))
        return cached_result
      end

      start_time = time_period.days.ago

      # First try the port-based approach
      result = analyze_metrics(start_time, repository)

      # If the result is empty, try a direct database query as a fallback
      if result[:total] == 0
        # Direct database query
        completed_count = DomainMetric.where(name: "github.workflow_run.completed")
                                      .where("recorded_at >= ?", start_time)
                                      .count

        success_count = DomainMetric.where(name: "github.workflow_run.conclusion.success")
                                    .where("recorded_at >= ?", start_time)
                                    .count

        failure_count = DomainMetric.where(name: "github.workflow_run.conclusion.failure")
                                    .where("recorded_at >= ?", start_time)
                                    .count

        if completed_count > 0 || success_count > 0 || failure_count > 0
          total_builds = completed_count > 0 ? completed_count : success_count + failure_count
          success_rate = total_builds > 0 ? (success_count.to_f / total_builds) * 100 : 0

          result[:total] = total_builds
          result[:success_rate] = success_rate.round(1)
        end
      end

      # Store in cache if available
      cache_results(result, time_period, repository) if @cache_port

      result
    end

    private

    # Fetch primary build metrics
    def fetch_build_metrics(start_time, repository)
      metrics = @storage_port.list_metrics(
        name: "github.workflow_run.completed",
        start_time: start_time
      )

      filter_by_repository(metrics, repository)
    end

    # Fetch build duration metrics
    def fetch_duration_metrics(start_time, repository)
      metrics = @storage_port.list_metrics(
        name: "github.ci.build.duration",
        start_time: start_time
      )

      # If no ci.build.duration metrics, try workflow metrics
      if metrics.empty?
        metrics = @storage_port.list_metrics(
          name: "github.workflow_run.duration",
          start_time: start_time
        )
      end

      filter_by_repository(metrics, repository)
    end

    # Fetch success metrics
    def fetch_success_metrics(start_time, repository)
      metrics = @storage_port.list_metrics(
        name: "github.workflow_run.conclusion.success",
        start_time: start_time
      )

      filter_by_repository(metrics, repository)
    end

    # Fetch failure metrics
    def fetch_failure_metrics(start_time, repository)
      metrics = @storage_port.list_metrics(
        name: "github.workflow_run.conclusion.failure",
        start_time: start_time
      )

      filter_by_repository(metrics, repository)
    end

    # Fetch check run metrics as fallback
    def fetch_check_run_metrics(start_time, repository)
      metrics = @storage_port.list_metrics(
        name: "github.check_run.completed",
        start_time: start_time
      )

      filter_by_repository(metrics, repository)
    end

    # Filter metrics by repository if provided
    def filter_by_repository(metrics, repository)
      return metrics unless repository.present?

      metrics.select { |metric| metric.dimensions["repository"] == repository }
    end

    # Apply direct DB fallback when results are empty but DB has data
    def apply_db_fallback(result, completed_count, success_count, failure_count)
      return unless result[:total] == 0 && (completed_count > 0 || success_count > 0 || failure_count > 0)

      total_builds = completed_count
      successful_builds = success_count

      # If no direct completion count but we have success/failure counts
      if total_builds == 0 && (successful_builds > 0 || failure_count > 0)
        total_builds = successful_builds + failure_count
      end

      # Calculate success rate
      success_rate = total_builds.positive? ? (successful_builds.to_f / total_builds) * 100 : 0

      # Update the result with actual counts
      result[:total] = total_builds
      result[:success_rate] = success_rate.round(2)
    end

    # Calculate core build performance metrics
    def calculate_metrics(build_metrics, duration_metrics, success_metrics, failure_metrics, start_time)
      # Total count metrics
      total_builds = build_metrics.size
      successful_builds = success_metrics.size
      failed_builds = failure_metrics.size

      # Calculate success rate
      success_rate = total_builds.positive? ? (successful_builds.to_f / total_builds) * 100 : 0

      # Calculate average duration
      total_duration = duration_metrics.sum(&:value)
      average_duration = duration_metrics.size.positive? ? total_duration / duration_metrics.size : 0

      # Group builds by day for time series data
      builds_by_day = group_metrics_by_day(build_metrics, start_time)
      success_by_day = group_metrics_by_day(success_metrics, start_time)

      # Group builds by workflow_name
      builds_by_workflow = build_metrics.group_by { |m| m.dimensions["workflow_name"] || "unknown" }
                                        .transform_values(&:size)
                                        .sort_by { |_, count| -count }
                                        .to_h

      # Get workflows with longest durations
      workflow_durations = duration_metrics.group_by { |m| m.dimensions["workflow_name"] || "unknown" }
                                           .transform_values { |metrics| metrics.sum(&:value) / metrics.size.to_f }
                                           .sort_by { |_, duration| -duration }
                                           .first(5)
                                           .to_h

      # Compile all metrics into result hash
      {
        total: total_builds,
        success_rate: success_rate.round(2),
        avg_duration: average_duration.round(2),
        builds_by_day: builds_by_day,
        success_by_day: success_by_day,
        builds_by_workflow: builds_by_workflow,
        longest_workflow_durations: workflow_durations,
        flaky_builds: identify_flaky_builds(build_metrics)
      }
    end

    # Group metrics by day for time series visualization
    def group_metrics_by_day(metrics, start_time)
      # Initialize result with all days in the period
      result = {}
      days = (Date.today - start_time.to_date).to_i + 1

      days.downto(0).each do |i|
        date = i.days.ago.to_date.to_s
        result[date] = 0
      end

      # Fill in actual values
      metrics.each do |metric|
        date = metric.timestamp.to_date.to_s
        result[date] = (result[date] || 0) + 1
      end

      result
    end

    # Identify potentially flaky builds (frequent failures followed by successes)
    def identify_flaky_builds(build_metrics)
      # Group by workflow name and job name
      workflows = build_metrics.group_by do |metric|
        [
          metric.dimensions["workflow_name"] || "unknown",
          metric.dimensions["job_name"] || "unknown"
        ]
      end

      flaky_builds = []

      workflows.each do |(workflow_name, job_name), metrics|
        # Sort by timestamp
        sorted_metrics = metrics.sort_by(&:timestamp)

        # Count transitions from success to failure or vice versa
        transitions = 0
        last_conclusion = nil

        sorted_metrics.each do |metric|
          conclusion = metric.dimensions["conclusion"]
          transitions += 1 if last_conclusion && conclusion != last_conclusion
          last_conclusion = conclusion
        end

        # If more than 25% of builds result in transitions, consider it flaky
        next unless metrics.size >= 4 && transitions >= (metrics.size * 0.25)

        flaky_builds << {
          workflow_name: workflow_name,
          job_name: job_name,
          transition_rate: (transitions.to_f / (metrics.size - 1) * 100).round(2)
        }
      end

      flaky_builds.sort_by { |b| -b[:transition_rate] }
    end

    # Get cached build performance metrics
    def from_cache(time_period, repository)
      key = cache_key(time_period, repository)
      cached = @cache_port.read(key)
      return nil unless cached

      begin
        JSON.parse(cached, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end
    end

    # Cache build performance metrics
    def cache_results(result, time_period, repository)
      key = cache_key(time_period, repository)
      @cache_port.write(key, result.to_json, expires_in: 1.hour)
    end

    # Get cache key for storing build performance metrics
    # @param time_period [Integer] Time period in days
    # @param repository [String, nil] Optional repository filter
    # @return [String] Cache key
    def cache_key(time_period, repository)
      repo_part = repository ? "repo_#{repository.gsub('/', '_')}" : "all_repos"
      "build_performance:days_#{time_period}:#{repo_part}"
    end

    # Extract metrics analysis to a separate method
    def analyze_metrics(start_time, repository)
      # Get direct DB counts for potential fallback
      completed_count = DomainMetric.where(name: "github.workflow_run.completed").count
      success_count = DomainMetric.where(name: "github.workflow_run.conclusion.success").count
      failure_count = DomainMetric.where(name: "github.workflow_run.conclusion.failure").count

      # Get workflow build metrics according to naming convention
      build_metrics = fetch_build_metrics(start_time, repository)
      duration_metrics = fetch_duration_metrics(start_time, repository)
      success_metrics = fetch_success_metrics(start_time, repository)
      failure_metrics = fetch_failure_metrics(start_time, repository)

      # Try alternative metrics if we don't have any data
      if build_metrics.empty? && success_metrics.empty? && failure_metrics.empty?
        check_metrics = fetch_check_run_metrics(start_time, repository)

        if check_metrics.any?
          build_metrics = check_metrics
          success_metrics = check_metrics.select { |m| m.dimensions["conclusion"] == "success" }
          failure_metrics = check_metrics.select { |m| m.dimensions["conclusion"] == "failure" }
        end
      end

      # Calculate metrics
      result = calculate_metrics(
        build_metrics,
        duration_metrics,
        success_metrics,
        failure_metrics,
        start_time
      )

      # Use direct DB counts as fallback if needed
      apply_db_fallback(result, completed_count, success_count, failure_count)

      result
    end
  end
end
