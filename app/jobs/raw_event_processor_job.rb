class RawEventProcessorJob < ApplicationJob
  queue_as :event_processing

  # Number of events to process in each batch
  BATCH_SIZE = 100

  # Maximum number of consecutive errors before the job gives up
  MAX_ERRORS = 3

  # Minimum time between re-enqueuing in seconds when no events
  REQUEUE_INTERVAL = 5

  def perform(worker_id = SecureRandom.uuid)
    # Only log worker start at debug level
    Rails.logger.debug { "RawEventProcessorJob started (worker_id: #{worker_id})" }
    error_count = 0

    # Get the queue adapter
    queue_adapter = DependencyContainer.resolve(:queue_port)

    # Process a batch of raw events
    processed_count = queue_adapter.process_raw_event_batch(worker_id)

    # Only log when we actually processed events
    Rails.logger.info("Processed #{processed_count} raw events (worker_id: #{worker_id})") if processed_count > 0

    # Always re-enqueue the job to process the next batch
    # This creates a continuous processing pattern without sleeping
    next_run = determine_wait_time(processed_count)
    RawEventProcessorJob.set(wait: next_run).perform_later(worker_id)

    # Only log re-enqueuing at debug level
    Rails.logger.debug do
      "Re-enqueued after processing #{processed_count} events with #{next_run}s delay (worker_id: #{worker_id})"
    end
  rescue StandardError => e
    error_count += 1
    Rails.logger.error("Error processing raw events batch (worker_id: #{worker_id}): #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    # If we've had too many errors, add a delay before retrying
    wait_time = error_count >= MAX_ERRORS ? 30.seconds : 5.seconds
    RawEventProcessorJob.set(wait: wait_time).perform_later(worker_id)

    # Keep error re-enqueuing at info level
    Rails.logger.info("Re-enqueued job after error with #{wait_time}s delay (worker_id: #{worker_id})")
  ensure
    # Only log completion at debug level
    Rails.logger.debug { "RawEventProcessorJob batch completed (worker_id: #{worker_id})" }
  end

  private

  # Determine how long to wait before processing the next batch
  # - If we processed items, re-enqueue immediately (0 seconds)
  # - If no items were processed, wait a bit to avoid hammering the queue
  def determine_wait_time(processed_count)
    if processed_count > 0
      0.seconds # No delay when we're actively processing
    else
      REQUEUE_INTERVAL.seconds # Small delay when there's nothing to process
    end
  end
end
