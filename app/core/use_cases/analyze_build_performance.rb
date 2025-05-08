# frozen_string_literal: true

module UseCases
  # AnalyzeBuildPerformance tracks build success rates and durations
  class AnalyzeBuildPerformance
    def initialize(storage_port:, cache_port: nil)
      @storage_port = storage_port
      @cache_port = cache_port
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

      # Get workflow job metrics related to builds
      build_metrics = @storage_port.list_metrics(
        name: "github.workflow_job.completed",
        start_time: start_time
      )

      # Filter by repository if provided
      if repository.present?
        build_metrics = build_metrics.select do |metric|
          metric.dimensions["repository"] == repository
        end
      end

      # Get CI build metrics for duration data
      duration_metrics = @storage_port.list_metrics(
        name: "github.ci.build.duration",
        start_time: start_time
      )

      # Filter by repository if provided
      if repository.present?
        duration_metrics = duration_metrics.select do |metric|
          metric.dimensions["repository"] == repository
        end
      end

      # Get successful and failed builds
      success_metrics = @storage_port.list_metrics(
        name: "github.workflow_job.conclusion.success",
        start_time: start_time
      )

      failure_metrics = @storage_port.list_metrics(
        name: "github.workflow_job.conclusion.failure",
        start_time: start_time
      )

      if repository.present?
        success_metrics = success_metrics.select { |m| m.dimensions["repository"] == repository }
        failure_metrics = failure_metrics.select { |m| m.dimensions["repository"] == repository }
      end

      # Calculate metrics
      result = calculate_metrics(
        build_metrics,
        duration_metrics,
        success_metrics,
        failure_metrics,
        start_time
      )

      # Cache results
      cache_results(result, time_period, repository) if @cache_port

      result
    end

    private

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
        total_builds: total_builds,
        successful_builds: successful_builds,
        failed_builds: failed_builds,
        success_rate: success_rate.round(2),
        average_build_duration: average_duration.round(2),
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
  end
end
