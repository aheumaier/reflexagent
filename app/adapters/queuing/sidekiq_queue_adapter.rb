# frozen_string_literal: true

require_relative "../../ports/queue_port"

module Queuing
  class SidekiqQueueAdapter
    include QueuePort

    # Queue configuration for the application
    QUEUES = {
      raw_events: "raw_events",
      event_processing: "event_processing",
      metric_calculation: "metric_calculation",
      anomaly_detection: "anomaly_detection"
    }

    # Maximum queue sizes for backpressure
    MAX_QUEUE_SIZE = {
      raw_events: 50_000,
      event_processing: 10_000,
      metric_calculation: 5_000,
      anomaly_detection: 1_000
    }

    # Queue processing batch sizes
    BATCH_SIZE = {
      raw_events: 100,
      event_processing: 50,
      metric_calculation: 25,
      anomaly_detection: 10
    }

    # Helper method to execute a block with a Redis connection
    # @param purpose [Symbol] The purpose of the connection (default, queue, etc.)
    # @yield [Redis] A Redis client
    # @return [Object] The result of the block
    def with_redis(purpose = :queue, &block)
      if defined?(Cache::RedisCache) && Cache::RedisCache.respond_to?(:with_redis)
        Cache::RedisCache.with_redis(purpose, &block)
      else
        # Fallback for test environment
        redis_client = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
        block.call(redis_client)
      end
    end

    # Enqueues a raw webhook payload for initial processing
    # @param raw_payload [String] The raw JSON webhook payload
    # @param source [String] The source of the webhook (github, jira, etc.)
    # @return [Boolean] True if the raw event was enqueued successfully
    def enqueue_raw_event(raw_payload, source)
      # Check for backpressure first
      if backpressure?
        Rails.logger.warn("Raw events queue is full - backpressure applied")
        raise QueueBackpressureError, "Too many pending events, please retry later"
      end

      # Create a simple payload wrapper with minimal metadata
      payload_wrapper = {
        id: SecureRandom.uuid,
        source: source,
        payload: raw_payload,
        received_at: Time.current.iso8601,
        status: "pending"
      }

      # Convert symbol keys to strings for Sidekiq JSON serialization
      string_keyed_payload = payload_wrapper.transform_keys(&:to_s)

      # Enqueue the raw event using Sidekiq
      RawEventJob.perform_async(string_keyed_payload)

      # Log with the expected message format
      Rails.logger.debug { "Enqueued raw #{source} event (id: #{payload_wrapper[:id]})" }
      true
    rescue QueueBackpressureError => e
      raise # Re-raise backpressure errors for appropriate client handling
    rescue StandardError => e
      Rails.logger.error("Failed to enqueue raw event: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      false
    end

    # Enqueues a job to process metric calculations for an event
    # @param event [Domain::Event] The event to process
    # @return [Boolean] True if the job was enqueued successfully
    def enqueue_metric_calculation(event)
      # Only pass the event ID to the job, not the entire serialized event
      # This ensures the job will look up the event from the database using the ID
      MetricCalculationJob.perform_async(event.id)
      Rails.logger.debug { "Enqueued metric calculation job for event: #{event.id}" }
      true
    rescue StandardError => e
      Rails.logger.error("Failed to enqueue metric calculation: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      false
    end

    # Enqueues a job to process anomaly detection for a metric
    # @param metric [Domain::Metric] The metric to analyze
    # @return [Boolean] True if the job was enqueued successfully
    def enqueue_anomaly_detection(metric)
      # Convert metric to hash with string keys for Sidekiq
      metric_data = serialize_metric(metric).transform_keys(&:to_s)
      AnomalyDetectionJob.perform_async(metric_data)
      Rails.logger.debug { "Enqueued anomaly detection job for metric: #{metric.id}" }
      true
    rescue StandardError => e
      Rails.logger.error("Failed to enqueue anomaly detection: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      false
    end

    # Process a batch of raw events (implemented for compatibility with the current design)
    # With Sidekiq, this is less important as individual jobs will process individual items
    # But we implement it for testing and backward compatibility
    # @param worker_id [String] An identifier for the worker process
    # @return [Integer] The number of raw events processed
    def process_raw_event_batch(worker_id)
      # This is a no-op in Sidekiq implementation as Sidekiq
      # processes individual jobs rather than batches
      # It's retained for compatibility with the existing interface
      Rails.logger.debug { "process_raw_event_batch called but not implemented in Sidekiq adapter" }
      0
    end

    # Gets current queue depths
    # @return [Hash] A hash of queue names and their current size
    def queue_depths
      # Use the Sidekiq API to fetch queue sizes
      stats = Sidekiq::Stats.new
      queue_sizes = stats.queues

      # Convert the queue names from Sidekiq format to our internal format
      QUEUES.transform_values do |queue_name|
        queue_sizes[queue_name] || 0
      end
    end

    # Checks if any queues are experiencing backpressure
    # @return [Boolean] True if any queue is at or above its maximum size
    def backpressure?
      queue_depths.any? do |queue_key, depth|
        depth >= MAX_QUEUE_SIZE[queue_key]
      end
    end

    # Add a method to get the next batch of events for testing
    # @param queue_type [Symbol] The type of queue to get events from
    # @param batch_size [Integer] The number of events to retrieve
    # @return [Array] An array of events
    def get_next_batch(queue_type, batch_size = BATCH_SIZE[queue_type])
      # Implementation for tests
      with_redis do |redis|
        queue_name = "queue:events:#{queue_type}"
        items = []

        batch_size.times do
          item = redis.lpop(queue_name)
          break unless item

          items << JSON.parse(item)
        end

        items
      end
    end

    # Error class for queue backpressure
    class QueueBackpressureError < StandardError; end

    private

    # Serializes an event for storage in Redis
    # This is a placeholder method that should be implemented
    # @param event [Domain::Event] The event to serialize
    # @return [Hash] A hash representation of the event
    def serialize_event(event)
      {
        id: event.id,
        type: event.name,
        source: event.source,
        timestamp: event.timestamp.iso8601,
        data: event.data,
        metadata: event.respond_to?(:metadata) ? (event.metadata || {}) : {}
      }
    end

    # Serializes a metric for storage in Redis
    # This is a placeholder method that should be implemented
    # @param metric [Domain::Metric] The metric to serialize
    # @return [Hash] A hash representation of the metric
    def serialize_metric(metric)
      {
        id: metric.id,
        name: metric.name,
        value: metric.value,
        timestamp: metric.timestamp.iso8601,
        dimensions: metric.dimensions
      }
    end
  end
end
