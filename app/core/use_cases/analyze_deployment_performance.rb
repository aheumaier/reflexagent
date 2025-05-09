# frozen_string_literal: true

module UseCases
  # AnalyzeDeploymentPerformance tracks deployment success rates and durations
  class AnalyzeDeploymentPerformance
    def initialize(storage_port:, cache_port: nil, metric_naming_port: nil, logger_port: nil)
      @storage_port = storage_port
      @cache_port = cache_port
      @metric_naming_port = metric_naming_port || DependencyContainer.resolve(:metric_naming_port)
      @logger_port = logger_port || Rails.logger
    end

    # @param time_period [Integer] The number of days to look back
    # @param repository [String, nil] Optional repository filter
    # @return [Hash] Deployment performance metrics
    def call(time_period:, repository: nil)
      if @cache_port && (cached_result = from_cache(time_period, repository))
        return cached_result
      end

      start_time = time_period.days.ago

      # Fetch all required metrics
      deploy_metrics = fetch_deployment_duration_metrics(start_time, repository)
      success_metrics = fetch_deployment_success_metrics(start_time, repository)
      failure_metrics = fetch_deployment_failure_metrics(start_time, repository)
      deploy_attempts = fetch_deployment_attempt_metrics(start_time, repository)
      deploy_failures = fetch_deployment_failure_rate_metrics(start_time, repository, failure_metrics)

      # Try generic metrics as last resort
      if success_metrics.empty? && failure_metrics.empty? && deploy_attempts.empty?
        generic_metrics = fetch_generic_deployment_metrics(start_time, repository)
        if generic_metrics.any?
          deploy_attempts = generic_metrics
          success_metrics = generic_metrics
        end
      end

      # Calculate metrics
      result = calculate_metrics(
        deploy_metrics,
        success_metrics,
        failure_metrics,
        deploy_attempts,
        deploy_failures,
        start_time
      )

      # Cache results
      cache_results(result, time_period, repository) if @cache_port

      result
    end

    private

    # Fetch deployment duration metrics with fallback options
    def fetch_deployment_duration_metrics(start_time, repository)
      metrics = @storage_port.list_metrics(
        name: "github.ci.deploy.duration",
        start_time: start_time
      )

      # Try alternative metrics if needed
      if metrics.empty?
        metrics = @storage_port.list_metrics(
          name: "github.deployment.duration",
          start_time: start_time
        )
      end

      filter_by_repository(metrics, repository)
    end

    # Fetch deployment success metrics with fallback options
    def fetch_deployment_success_metrics(start_time, repository)
      metrics = @storage_port.list_metrics(
        name: "github.ci.deploy.completed",
        start_time: start_time
      )

      # Try alternative metrics if needed
      if metrics.empty?
        metrics = @storage_port.list_metrics(
          name: "github.deployment_status.success",
          start_time: start_time
        )
      end

      filter_by_repository(metrics, repository)
    end

    # Fetch deployment failure metrics with fallback options
    def fetch_deployment_failure_metrics(start_time, repository)
      metrics = @storage_port.list_metrics(
        name: "github.ci.deploy.failed",
        start_time: start_time
      )

      # Try alternative metrics if needed
      if metrics.empty?
        metrics = @storage_port.list_metrics(
          name: "github.deployment_status.failure",
          start_time: start_time
        )
      end

      filter_by_repository(metrics, repository)
    end

    # Fetch deployment attempt metrics with fallback options
    def fetch_deployment_attempt_metrics(start_time, repository)
      metrics = @storage_port.list_metrics(
        name: "dora.deployment_frequency",
        start_time: start_time
      )

      # Try alternative metrics if needed
      if metrics.empty?
        metrics = @storage_port.list_metrics(
          name: "github.deployment.created",
          start_time: start_time
        )
      end

      filter_by_repository(metrics, repository)
    end

    # Fetch deployment failure rate metrics with fallback options
    def fetch_deployment_failure_rate_metrics(start_time, repository, fallback_metrics)
      metrics = @storage_port.list_metrics(
        name: "dora.change_failure_rate",
        start_time: start_time
      )

      # Use failure metrics as fallback if needed
      metrics = fallback_metrics if metrics.empty?

      filter_by_repository(metrics, repository)
    end

    # Fetch generic deployment metrics as a last resort
    def fetch_generic_deployment_metrics(start_time, repository)
      metrics = @storage_port.list_metrics_with_name_pattern(
        "%deploy%",
        start_time: start_time
      )

      filter_by_repository(metrics, repository)
    end

    # Filter metrics by repository if provided
    def filter_by_repository(metrics, repository)
      return metrics unless repository.present?

      metrics.select { |metric| metric.dimensions["repository"] == repository }
    end

    # Calculate core deployment performance metrics
    def calculate_metrics(
      deploy_metrics,
      success_metrics,
      failure_metrics,
      deploy_attempts,
      deploy_failures,
      start_time
    )
      # Total count metrics
      total_deploys = success_metrics.size + failure_metrics.size
      successful_deploys = success_metrics.size
      failed_deploys = failure_metrics.size

      # Calculate success rate
      success_rate = total_deploys.positive? ? (successful_deploys.to_f / total_deploys) * 100 : 0

      # Calculate average duration
      total_duration = deploy_metrics.sum(&:value)
      average_duration = deploy_metrics.size.positive? ? total_duration.to_f / deploy_metrics.size : 0

      # Group deployments by day for time series data
      deploys_by_day = group_metrics_by_day(deploy_attempts, start_time)
      failures_by_day = group_metrics_by_day(deploy_failures, start_time)

      # Calculate daily success rates
      success_rate_by_day = calculate_daily_success_rates(deploys_by_day, failures_by_day)

      # Group deployments by workflow
      deploys_by_workflow = deploy_attempts.group_by { |m| m.dimensions["workflow_name"] || "unknown" }
                                           .transform_values(&:size)
                                           .sort_by { |_, count| -count }
                                           .to_h

      # Group deployment durations by environment
      durations_by_env = calculate_durations_by_environment(deploy_metrics)

      # Calculate deployment frequency (deploys per day)
      days_count = (Date.today - start_time.to_date).to_i + 1
      deployment_frequency = days_count.positive? ? (total_deploys.to_f / days_count) : 0

      # Get most common failure reasons
      failure_reasons = extract_failure_reasons(deploy_failures)

      # Compile all metrics into result hash
      {
        total: total_deploys,
        success_rate: success_rate.round(2),
        avg_duration: average_duration.round(2),
        deployment_frequency: deployment_frequency.round(2),
        deploys_by_day: deploys_by_day,
        success_rate_by_day: success_rate_by_day,
        deploys_by_workflow: deploys_by_workflow,
        durations_by_environment: durations_by_env,
        common_failure_reasons: failure_reasons
      }
    end

    # Calculate daily success rates from deploy and failure data
    def calculate_daily_success_rates(deploys_by_day, failures_by_day)
      success_rate_by_day = {}
      deploys_by_day.each do |date, count|
        failures = failures_by_day[date] || 0
        success_rate_by_day[date] = count.positive? ? ((count - failures).to_f / count) * 100 : 0
      end
      success_rate_by_day
    end

    # Calculate deployment durations by environment
    def calculate_durations_by_environment(deploy_metrics)
      deploy_metrics.group_by { |m| m.dimensions["environment"] || "production" }
                    .transform_values do |metrics|
        metrics.sum(&:value) / metrics.size.to_f
      end
                   .sort_by { |_, duration| -duration }
                    .to_h
    end

    # Extract failure reasons from metrics
    def extract_failure_reasons(deploy_failures)
      failure_reasons = {}
      deploy_failures.each do |metric|
        reason = metric.dimensions["reason"] || metric.dimensions[:reason] || "unknown"
        failure_reasons[reason] ||= 0
        failure_reasons[reason] += 1
      end
      failure_reasons.sort_by { |_, count| -count }.to_h
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

    # Get cached deployment performance metrics
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

    # Cache deployment performance metrics
    def cache_results(result, time_period, repository)
      key = cache_key(time_period, repository)
      @cache_port.write(key, result.to_json, expires_in: 1.hour)
    end

    # Get cache key for storing deployment performance metrics
    # @param time_period [Integer] Time period in days
    # @param repository [String, nil] Optional repository filter
    # @return [String] Cache key
    def cache_key(time_period, repository)
      repo_part = repository ? "repo_#{repository.gsub('/', '_')}" : "all_repos"
      "deployment_performance:days_#{time_period}:#{repo_part}"
    end
  end
end
