# frozen_string_literal: true

module Repositories
  # DoraMetricsRepository provides specialized methods for DORA metrics
  # that aggregate data across multiple source systems
  class DoraMetricsRepository < BaseMetricRepository
    # DORA metrics performance thresholds (based on Accelerate book)
    DEPLOYMENT_FREQUENCY_THRESHOLDS = {
      elite: 7.0, # Multiple deploys per day (7+ per week)
      high: 1.0,  # Between once per day and once per week
      medium: 0.25 # Between once per week and once per month
      # anything less is considered "low"
    }.freeze

    LEAD_TIME_THRESHOLDS = {
      elite: 24, # Less than one day (in hours)
      high: 168, # Less than one week (in hours)
      medium: 720 # Less than one month (in hours)
      # anything more is considered "low"
    }.freeze

    MTTR_THRESHOLDS = {
      elite: 1, # Less than one hour
      high: 24, # Less than one day
      medium: 168 # Less than one week
      # anything more is considered "low"
    }.freeze

    CHANGE_FAILURE_RATE_THRESHOLDS = {
      elite: 15, # 0-15%
      high: 30, # 16-30%
      medium: 45 # 31-45%
      # anything more is considered "low"
    }.freeze

    # Calculate deployment frequency for a team/project
    # @param team_id [String, nil] Optional team identifier
    # @param repository [String, nil] Optional repository filter
    # @param start_time [Time] The start time for analysis
    # @param end_time [Time] The end time for analysis
    # @return [Hash] Deployment frequency statistics including count and frequency label
    def deployment_frequency(start_time:, end_time:, team_id: nil, repository: nil)
      context = {
        start_time: start_time,
        end_time: end_time,
        team_id: team_id,
        repository: repository
      }

      begin
        log_debug("Calculating deployment frequency from #{start_time} to #{end_time}")

        # Build dimensions filter
        dimensions = {}
        dimensions[:team_id] = team_id if team_id
        dimensions[:repository] = repository if repository

        # Find all deployment metrics across different sources
        deployments = []

        # First, find GitHub deployments
        github_deployments = find_metrics_by_name_and_dimensions(
          "github.deployment.completed",
          dimensions,
          start_time
        ).select { |m| m.timestamp <= end_time }

        deployments.concat(github_deployments)

        # Find deployments from other sources (can add more sources here)
        # Example:
        # jenkins_deployments = find_metrics_by_name_and_dimensions(
        #   "jenkins.deploy.completed",
        #   dimensions,
        #   start_time
        # ).select { |m| m.timestamp <= end_time }
        #
        # deployments.concat(jenkins_deployments)

        # Calculate the deployment metrics
        deployment_count = deployments.size
        days_in_period = ((end_time - start_time) / 86_400).to_f # Convert seconds to days
        frequency_per_day = days_in_period.zero? ? 0 : deployment_count / days_in_period
        frequency_per_week = frequency_per_day * 7

        # Determine performance level based on frequency per week
        performance_level = deployment_frequency_label(frequency_per_week)

        {
          deployment_count: deployment_count,
          days_in_period: days_in_period.round(1),
          frequency_per_day: frequency_per_day.round(2),
          frequency_per_week: frequency_per_week.round(2),
          performance_level: performance_level
        }
      rescue StandardError => e
        handle_query_error("deployment_frequency", e, context)
      end
    end

    # Calculate lead time for changes
    # @param team_id [String, nil] Optional team identifier
    # @param repository [String, nil] Optional repository filter
    # @param start_time [Time] The start time for analysis
    # @param end_time [Time] The end time for analysis
    # @return [Hash] Lead time statistics including average time and performance label
    def lead_time_for_changes(start_time:, end_time:, team_id: nil, repository: nil)
      context = {
        start_time: start_time,
        end_time: end_time,
        team_id: team_id,
        repository: repository
      }

      begin
        log_debug("Calculating lead time for changes from #{start_time} to #{end_time}")

        # Build dimensions filter
        dimensions = {}
        dimensions[:team_id] = team_id if team_id
        dimensions[:repository] = repository if repository

        # Find all lead time metrics across different sources
        lead_times = []

        # First, find GitHub lead times
        github_lead_times = find_metrics_by_name_and_dimensions(
          "github.ci.lead_time",
          dimensions,
          start_time
        ).select { |m| m.timestamp <= end_time }

        lead_times.concat(github_lead_times)

        # Find lead times from other sources (can add more sources here)
        # Example:
        # gitlab_lead_times = find_metrics_by_name_and_dimensions(
        #   "gitlab.ci.lead_time",
        #   dimensions,
        #   start_time
        # ).select { |m| m.timestamp <= end_time }
        #
        # lead_times.concat(gitlab_lead_times)

        # Calculate lead time statistics
        if lead_times.empty?
          return {
            change_count: 0,
            average_lead_time_hours: 0,
            median_lead_time_hours: 0,
            p90_lead_time_hours: 0,
            performance_level: "unknown"
          }
        end

        # Extract lead time values (assuming they're stored in hours)
        lead_time_values = lead_times.map(&:value)

        # Calculate statistics
        average_lead_time = lead_time_values.sum / lead_time_values.size
        sorted_lead_times = lead_time_values.sort
        median_lead_time = if lead_time_values.size.odd?
                             sorted_lead_times[lead_time_values.size / 2]
                           else
                             (sorted_lead_times[(lead_time_values.size / 2) - 1] + sorted_lead_times[lead_time_values.size / 2]) / 2.0
                           end

        # Calculate 90th percentile
        p90_index = (lead_time_values.size * 0.9).ceil - 1
        p90_lead_time = sorted_lead_times[p90_index]

        # Determine performance level based on median lead time
        performance_level = lead_time_label(median_lead_time)

        {
          change_count: lead_times.size,
          average_lead_time_hours: average_lead_time.round(2),
          median_lead_time_hours: median_lead_time.round(2),
          p90_lead_time_hours: p90_lead_time.round(2),
          performance_level: performance_level
        }
      rescue StandardError => e
        handle_query_error("lead_time_for_changes", e, context)
      end
    end

    # Calculate time to restore service
    # @param team_id [String, nil] Optional team identifier
    # @param service [String, nil] Optional service/application filter
    # @param start_time [Time] The start time for analysis
    # @param end_time [Time] The end time for analysis
    # @return [Hash] MTTR statistics including average time and performance label
    def time_to_restore_service(start_time:, end_time:, team_id: nil, service: nil)
      context = {
        start_time: start_time,
        end_time: end_time,
        team_id: team_id,
        service: service
      }

      begin
        log_debug("Calculating time to restore service from #{start_time} to #{end_time}")

        # Build dimensions filter
        dimensions = {}
        dimensions[:team_id] = team_id if team_id
        dimensions[:service] = service if service

        # Find all incident restoration metrics across different sources
        restore_times = []

        # Find GitHub/Jira/PagerDuty incident resolution metrics
        # Different sources might track this differently
        github_restore_times = find_metrics_by_name_and_dimensions(
          "github.ci.deploy.incident.resolution_time",
          dimensions,
          start_time
        ).select { |m| m.timestamp <= end_time }

        restore_times.concat(github_restore_times)

        # Add other sources here as needed

        # Calculate MTTR statistics
        if restore_times.empty?
          return {
            incident_count: 0,
            average_restore_time_hours: 0,
            median_restore_time_hours: 0,
            p90_restore_time_hours: 0,
            performance_level: "unknown"
          }
        end

        # Extract restore time values (assuming they're stored in hours)
        restore_time_values = restore_times.map(&:value)

        # Calculate statistics
        average_restore_time = restore_time_values.sum / restore_time_values.size
        sorted_restore_times = restore_time_values.sort
        median_restore_time = if restore_time_values.size.odd?
                                sorted_restore_times[restore_time_values.size / 2]
                              else
                                (sorted_restore_times[(restore_time_values.size / 2) - 1] + sorted_restore_times[restore_time_values.size / 2]) / 2.0
                              end

        # Calculate 90th percentile
        p90_index = (restore_time_values.size * 0.9).ceil - 1
        p90_restore_time = sorted_restore_times[p90_index]

        # Determine performance level based on median restore time
        performance_level = mttr_label(median_restore_time)

        {
          incident_count: restore_times.size,
          average_restore_time_hours: average_restore_time.round(2),
          median_restore_time_hours: median_restore_time.round(2),
          p90_restore_time_hours: p90_restore_time.round(2),
          performance_level: performance_level
        }
      rescue StandardError => e
        handle_query_error("time_to_restore_service", e, context)
      end
    end

    # Calculate change failure rate
    # @param team_id [String, nil] Optional team identifier
    # @param repository [String, nil] Optional repository filter
    # @param start_time [Time] The start time for analysis
    # @param end_time [Time] The end time for analysis
    # @return [Hash] Failure rate statistics including percentage and performance label
    def change_failure_rate(start_time:, end_time:, team_id: nil, repository: nil)
      context = {
        start_time: start_time,
        end_time: end_time,
        team_id: team_id,
        repository: repository
      }

      begin
        log_debug("Calculating change failure rate from #{start_time} to #{end_time}")

        # Build dimensions filter
        dimensions = {}
        dimensions[:team_id] = team_id if team_id
        dimensions[:repository] = repository if repository

        # Find all deployment metrics and failed deployment metrics
        total_deployments = []
        failed_deployments = []

        # GitHub deployments
        github_total = find_metrics_by_name_and_dimensions(
          "github.deployment.total",
          dimensions,
          start_time
        ).select { |m| m.timestamp <= end_time }

        github_failed = find_metrics_by_name_and_dimensions(
          "github.deployment.failure",
          dimensions,
          start_time
        ).select { |m| m.timestamp <= end_time }

        total_deployments.concat(github_total)
        failed_deployments.concat(github_failed)

        # Add other sources here as needed

        # Calculate failure rate
        total_count = total_deployments.sum(&:value).to_i
        failed_count = failed_deployments.sum(&:value).to_i

        if total_count.zero?
          return {
            total_deployments: 0,
            failed_deployments: 0,
            failure_rate_percentage: 0,
            performance_level: "unknown"
          }
        end

        failure_rate = (failed_count.to_f / total_count) * 100

        # Determine performance level based on failure rate
        performance_level = failure_rate_label(failure_rate)

        {
          total_deployments: total_count,
          failed_deployments: failed_count,
          failure_rate_percentage: failure_rate.round(2),
          performance_level: performance_level
        }
      rescue StandardError => e
        handle_query_error("change_failure_rate", e, context)
      end
    end

    # Calculate overall DORA performance level
    # @param team_id [String, nil] Optional team identifier
    # @param repository [String, nil] Optional repository filter
    # @param start_time [Time] The start time for analysis
    # @param end_time [Time] The end time for analysis
    # @return [Hash] Overall performance assessment across all four metrics
    def overall_performance(start_time:, end_time:, team_id: nil, repository: nil)
      context = {
        start_time: start_time,
        end_time: end_time,
        team_id: team_id,
        repository: repository
      }

      begin
        # Calculate each of the four DORA metrics
        df = deployment_frequency(start_time: start_time, end_time: end_time, team_id: team_id, repository: repository)
        lt = lead_time_for_changes(start_time: start_time, end_time: end_time, team_id: team_id, repository: repository)
        mttr = time_to_restore_service(start_time: start_time, end_time: end_time, team_id: team_id,
                                       service: repository)
        cfr = change_failure_rate(start_time: start_time, end_time: end_time, team_id: team_id, repository: repository)

        # Map performance levels to numeric scores
        performance_scores = {
          "elite" => 4,
          "high" => 3,
          "medium" => 2,
          "low" => 1,
          "unknown" => 0
        }

        # Calculate individual scores
        df_score = performance_scores[df[:performance_level]]
        lt_score = performance_scores[lt[:performance_level]]
        mttr_score = performance_scores[mttr[:performance_level]]
        cfr_score = performance_scores[cfr[:performance_level]]

        # Calculate average score (only for known metrics)
        known_scores = [df_score, lt_score, mttr_score, cfr_score].reject(&:zero?)
        average_score = known_scores.empty? ? 0 : known_scores.sum.to_f / known_scores.size

        # Map average score back to performance level
        performance_levels = {
          4 => "elite",
          3 => "high",
          2 => "medium",
          1 => "low",
          0 => "unknown"
        }

        # Round to nearest integer for mapping
        overall_level = performance_levels[average_score.round]

        {
          deployment_frequency: df,
          lead_time: lt,
          time_to_restore: mttr,
          change_failure_rate: cfr,
          average_score: average_score.round(2),
          overall_performance_level: overall_level
        }
      rescue StandardError => e
        handle_query_error("overall_performance", e, context)
      end
    end

    # Get DORA trend data for visualization
    # @param metric [String] Which DORA metric to analyze ('deployment_frequency', 'lead_time', etc.)
    # @param team_id [String, nil] Optional team identifier
    # @param repository [String, nil] Optional repository filter
    # @param start_time [Time] The start time for analysis
    # @param end_time [Time] The end time for analysis
    # @param interval [String] Time interval for grouping ('day', 'week', 'month')
    # @return [Array<Hash>] Trend data points for the requested metric
    def trend_data(metric:, start_time:, end_time:, team_id: nil, repository: nil, interval: "week")
      context = {
        metric: metric,
        start_time: start_time,
        end_time: end_time,
        team_id: team_id,
        repository: repository,
        interval: interval
      }

      begin
        log_debug("Getting trend data for #{metric} from #{start_time} to #{end_time} with interval #{interval}")

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

        # Calculate number of intervals
        total_seconds = end_time - start_time
        num_intervals = (total_seconds / interval_seconds).ceil

        # Generate data points for each interval
        data_points = []

        num_intervals.times do |i|
          interval_start = start_time + (i * interval_seconds)
          interval_end = [interval_start + interval_seconds, end_time].min

          # Calculate metric for this interval
          result = case metric.downcase
                   when "deployment_frequency"
                     deployment_frequency(start_time: interval_start, end_time: interval_end, team_id: team_id,
                                          repository: repository)
                   when "lead_time"
                     lead_time_for_changes(start_time: interval_start, end_time: interval_end, team_id: team_id,
                                           repository: repository)
                   when "time_to_restore"
                     time_to_restore_service(start_time: interval_start, end_time: interval_end, team_id: team_id,
                                             service: repository)
                   when "change_failure_rate"
                     change_failure_rate(start_time: interval_start, end_time: interval_end, team_id: team_id,
                                         repository: repository)
                   else
                     raise Repositories::Errors::InvalidMetricNameError.new(
                       metric,
                       { available_metrics: ["deployment_frequency", "lead_time", "time_to_restore",
                                             "change_failure_rate"] }
                     )
                   end

          next unless result

          # Extract the primary value for this metric
          value = case metric.downcase
                  when "deployment_frequency"
                    result[:frequency_per_week]
                  when "lead_time"
                    result[:median_lead_time_hours]
                  when "time_to_restore"
                    result[:median_restore_time_hours]
                  when "change_failure_rate"
                    result[:failure_rate_percentage]
                  end

          data_points << {
            start_time: interval_start,
            end_time: interval_end,
            value: value,
            performance_level: result[:performance_level]
          }
        end

        data_points
      rescue StandardError => e
        handle_query_error("trend_data", e, context)
      end
    end

    protected

    # Calculate frequency label based on deployment count and time period
    # @param frequency_per_week [Float] Deployments per week
    # @return [String] Performance label ('elite', 'high', 'medium', 'low')
    def deployment_frequency_label(frequency_per_week)
      if frequency_per_week >= DEPLOYMENT_FREQUENCY_THRESHOLDS[:elite]
        "elite"
      elsif frequency_per_week >= DEPLOYMENT_FREQUENCY_THRESHOLDS[:high]
        "high"
      elsif frequency_per_week >= DEPLOYMENT_FREQUENCY_THRESHOLDS[:medium]
        "medium"
      else
        "low"
      end
    end

    # Calculate lead time label based on average lead time in hours
    # @param hours [Float] Average lead time in hours
    # @return [String] Performance label ('elite', 'high', 'medium', 'low')
    def lead_time_label(hours)
      if hours <= LEAD_TIME_THRESHOLDS[:elite]
        "elite"
      elsif hours <= LEAD_TIME_THRESHOLDS[:high]
        "high"
      elsif hours <= LEAD_TIME_THRESHOLDS[:medium]
        "medium"
      else
        "low"
      end
    end

    # Calculate MTTR label based on average restore time in hours
    # @param hours [Float] Average time to restore in hours
    # @return [String] Performance label ('elite', 'high', 'medium', 'low')
    def mttr_label(hours)
      if hours <= MTTR_THRESHOLDS[:elite]
        "elite"
      elsif hours <= MTTR_THRESHOLDS[:high]
        "high"
      elsif hours <= MTTR_THRESHOLDS[:medium]
        "medium"
      else
        "low"
      end
    end

    # Calculate change failure rate label based on failure percentage
    # @param percentage [Float] Failure rate as a percentage
    # @return [String] Performance label ('elite', 'high', 'medium', 'low')
    def failure_rate_label(percentage)
      if percentage <= CHANGE_FAILURE_RATE_THRESHOLDS[:elite]
        "elite"
      elsif percentage <= CHANGE_FAILURE_RATE_THRESHOLDS[:high]
        "high"
      elsif percentage <= CHANGE_FAILURE_RATE_THRESHOLDS[:medium]
        "medium"
      else
        "low"
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
