# frozen_string_literal: true

module UseCases
  # AnalyzeDeploymentPerformance tracks deployment success rates and durations
  class AnalyzeDeploymentPerformance
    def initialize(storage_port:, cache_port: nil)
      @storage_port = storage_port
      @cache_port = cache_port
    end

    # @param time_period [Integer] The number of days to look back
    # @param repository [String, nil] Optional repository filter
    # @return [Hash] Deployment performance metrics
    def call(time_period:, repository: nil)
      if @cache_port && (cached_result = from_cache(time_period, repository))
        return cached_result
      end

      start_time = time_period.days.ago

      # Get deployment metrics from workflow jobs
      deploy_metrics = @storage_port.list_metrics(
        name: "github.ci.deploy.duration",
        start_time: start_time
      )

      # Filter by repository if provided
      if repository.present?
        deploy_metrics = deploy_metrics.select do |metric|
          metric.dimensions["repository"] == repository
        end
      end

      # Get successful and failed deployments
      success_metrics = @storage_port.list_metrics(
        name: "github.ci.deploy.completed",
        start_time: start_time
      )

      failure_metrics = @storage_port.list_metrics(
        name: "github.ci.deploy.failed",
        start_time: start_time
      )

      # Get DORA metrics
      dora_deploy_attempts = @storage_port.list_metrics(
        name: "dora.deployment.attempt",
        start_time: start_time
      )

      dora_deploy_failures = @storage_port.list_metrics(
        name: "dora.deployment.failure",
        start_time: start_time
      )

      if repository.present?
        success_metrics = success_metrics.select { |m| m.dimensions["repository"] == repository }
        failure_metrics = failure_metrics.select { |m| m.dimensions["repository"] == repository }
        dora_deploy_attempts = dora_deploy_attempts.select { |m| m.dimensions["repository"] == repository }
        dora_deploy_failures = dora_deploy_failures.select { |m| m.dimensions["repository"] == repository }
      end

      # Calculate metrics
      result = calculate_metrics(
        deploy_metrics,
        success_metrics,
        failure_metrics,
        dora_deploy_attempts,
        dora_deploy_failures,
        start_time
      )

      # Cache results
      cache_results(result, time_period, repository) if @cache_port

      result
    end

    private

    # Calculate core deployment performance metrics
    def calculate_metrics(
      deploy_metrics,
      success_metrics,
      failure_metrics,
      dora_deploy_attempts,
      dora_deploy_failures,
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
      deploys_by_day = group_metrics_by_day(dora_deploy_attempts, start_time)
      failures_by_day = group_metrics_by_day(dora_deploy_failures, start_time)

      # Calculate daily success rates
      success_rate_by_day = {}
      deploys_by_day.each do |date, count|
        failures = failures_by_day[date] || 0
        success_rate_by_day[date] = count.positive? ? ((count - failures).to_f / count) * 100 : 0
      end

      # Group deployments by workflow
      deploys_by_workflow = dora_deploy_attempts.group_by { |m| m.dimensions["workflow_name"] || "unknown" }
                                                .transform_values(&:size)
                                                .sort_by { |_, count| -count }
                                                .to_h

      # Group deployment durations by environment (if available)
      durations_by_env = deploy_metrics.group_by { |m| m.dimensions["environment"] || "production" }
                                       .transform_values do |metrics|
        metrics.sum(&:value) / metrics.size.to_f
      end
                                     .sort_by { |_, duration| -duration }
                                       .to_h

      # Calculate deployment frequency (deploys per day)
      days_count = (Date.today - start_time.to_date).to_i + 1
      deployment_frequency = days_count.positive? ? (total_deploys.to_f / days_count) : 0

      # Get most common failure reasons
      failure_reasons = {}
      dora_deploy_failures.each do |metric|
        # Use string keys consistently for dimensions
        reason = metric.dimensions["reason"] || metric.dimensions[:reason] || "unknown"
        failure_reasons[reason] ||= 0
        failure_reasons[reason] += 1
      end
      failure_reasons = failure_reasons.sort_by { |_, count| -count }.to_h

      # Compile all metrics into result hash
      {
        total_deploys: total_deploys,
        successful_deploys: successful_deploys,
        failed_deploys: failed_deploys,
        success_rate: success_rate.round(2),
        average_deploy_duration: average_duration.round(2),
        deployment_frequency: deployment_frequency.round(2),
        deploys_by_day: deploys_by_day,
        success_rate_by_day: success_rate_by_day,
        deploys_by_workflow: deploys_by_workflow,
        durations_by_environment: durations_by_env,
        common_failure_reasons: failure_reasons
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
