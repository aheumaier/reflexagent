# frozen_string_literal: true

# Configuration for event processing workers
WORKER_COUNT = ENV.fetch("EVENT_WORKER_COUNT", 2).to_i
MONITOR_INTERVAL = ENV.fetch("QUEUE_MONITOR_INTERVAL", 30).to_i

# Start the raw event processors in the background
Rails.application.config.after_initialize do
  # Only start the processors in server mode, not in console, rake tasks, etc.
  if defined?(Rails::Server) || ENV["PROCESS_EVENTS"] == "true"
    Rails.logger.info "Starting #{WORKER_COUNT} raw event processor workers..."

    # Start queue monitoring service
    Rails.logger.info "Starting queue monitoring service (interval: #{MONITOR_INTERVAL}s)..."
    QueueMonitorService.schedule_reporting(MONITOR_INTERVAL)

    # Start workers with a small delay to ensure the Rails app is fully initialized
    Thread.new do
      # Small delay to ensure Rails is fully initialized
      sleep 5

      # Start multiple workers for better concurrency
      WORKER_COUNT.times do |i|
        worker_id = "worker-#{i}-#{SecureRandom.hex(4)}"
        RawEventProcessorJob.perform_later(worker_id)
        Rails.logger.info "Raw event processor worker enqueued (worker_id: #{worker_id})"
      end
    rescue StandardError => e
      Rails.logger.error "Failed to start raw event processors: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  else
    Rails.logger.info "Raw event processors not started (not in server mode)"
  end
end
