# frozen_string_literal: true

# Service for monitoring queue statistics and performance
class QueueMonitorService
  class << self
    # Store previous stats to avoid logging when nothing changes
    @previous_stats = nil
    @consecutive_unchanged = 0
    @max_silent_reports = 5 # Only log every 5 times if unchanged

    # Report queue metrics to the application's monitoring system
    # @return [Hash] The current queue stats
    def report_metrics
      stats = collect_queue_stats

      # Only log if something has changed or we've been silent too long
      if should_log_stats?(stats)
        log_queue_stats(stats)
        @consecutive_unchanged = 0
      else
        @consecutive_unchanged += 1
      end

      publish_stats_to_metrics(stats)
      @previous_stats = stats
      stats
    end

    # Schedule regular reporting of queue metrics
    # @param interval [Integer] The reporting interval in seconds
    def schedule_reporting(interval = 60)
      return if @reporting_scheduled

      Thread.new do
        loop do
          report_metrics
        rescue StandardError => e
          Rails.logger.error("Error reporting queue metrics: #{e.message}")
        ensure
          sleep interval
        end
      end

      @reporting_scheduled = true
    end

    private

    # Determine if we should log the current stats
    # @param stats [Hash] The current queue statistics
    # @return [Boolean] Whether to log the stats
    def should_log_stats?(stats)
      return true if @previous_stats.nil? # Always log the first time
      return true if @consecutive_unchanged >= @max_silent_reports # Log periodically even if unchanged

      # Check if any queue depths have changed significantly
      previous_depths = @previous_stats[:queue_depths]
      current_depths = stats[:queue_depths]

      # Log if backpressure status changed
      return true if @previous_stats[:backpressure] != stats[:backpressure]

      # Log if any queue changed by more than 10 items
      previous_depths.any? do |queue, depth|
        (current_depths[queue] - depth).abs > 10
      end
    end

    # Collect statistics about all queues
    # @return [Hash] The queue statistics
    def collect_queue_stats
      queue_adapter = DependencyContainer.resolve(:queue_port)

      {
        queue_depths: queue_adapter.queue_depths,
        backpressure: queue_adapter.backpressure?,
        timestamp: Time.current.iso8601,
        latency: calculate_queue_latency(queue_adapter)
      }
    end

    # Log queue statistics to the Rails logger
    # @param stats [Hash] The queue statistics
    def log_queue_stats(stats)
      depths = stats[:queue_depths]

      Rails.logger.info("Queue Monitor | " \
                        "raw_events: #{depths[:raw_events]} | " \
                        "event_processing: #{depths[:event_processing]} | " \
                        "metric_calculation: #{depths[:metric_calculation]} | " \
                        "backpressure: #{stats[:backpressure]}")
    end

    # Publish statistics to the application's metrics system
    # @param stats [Hash] The queue statistics
    def publish_stats_to_metrics(stats)
      # This would integrate with your metrics system (e.g., Prometheus, StatsD)
      # Implementation depends on your monitoring infrastructure
    end

    # Calculate queue latency (time between enqueue and processing)
    # @param queue_adapter [Adapters::Queue::RedisQueueAdapter] The queue adapter
    # @return [Hash] Latency metrics by queue
    def calculate_queue_latency(queue_adapter)
      # Implementation would sample items in the queue
      # to estimate time between enqueue and expected processing
      {}
    end
  end
end
