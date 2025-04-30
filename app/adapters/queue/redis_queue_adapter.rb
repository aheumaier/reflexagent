module Adapters
  module Queue
    class RedisQueueAdapter
      include Ports::QueuePort

      # Constants for queue configuration
      QUEUES = {
        raw_events: "queue:events:raw",
        event_processing: "queue:events:processing",
        metric_calculation: "queue:metrics:calculation",
        anomaly_detection: "queue:anomalies:detection"
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

      # TTL for items in queue (in seconds)
      QUEUE_TTL = 3 * 24 * 60 * 60 # 3 days

      # Enqueues a raw webhook payload for initial processing
      # This is called directly from the webhook controller
      # @param raw_payload [String] The raw JSON webhook payload
      # @param source [String] The source of the webhook (github, jira, etc.)
      # @return [Boolean] True if the raw event was enqueued successfully
      def enqueue_raw_event(raw_payload, source)
        # Check for backpressure first
        if queue_full?(:raw_events)
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

        # Enqueue the raw event
        enqueue_item(:raw_events, payload_wrapper)
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
      # @param event [Core::Domain::Event] The event to process
      # @return [Boolean] True if the job was enqueued successfully
      def enqueue_metric_calculation(event)
        enqueue_item(:metric_calculation, serialize_event(event))
        Rails.logger.debug { "Enqueued metric calculation job for event: #{event.id}" }
        true
      rescue StandardError => e
        Rails.logger.error("Failed to enqueue metric calculation: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        false
      end

      # Enqueues a job to process anomaly detection for a metric
      # @param metric [Core::Domain::Metric] The metric to analyze
      # @return [Boolean] True if the job was enqueued successfully
      def enqueue_anomaly_detection(metric)
        enqueue_item(:anomaly_detection, serialize_metric(metric))
        Rails.logger.debug { "Enqueued anomaly detection job for metric: #{metric.id}" }
        true
      rescue StandardError => e
        Rails.logger.error("Failed to enqueue anomaly detection: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        false
      end

      # Gets the current queue depths
      # @return [Hash] A hash of queue names and their current size
      def queue_depths
        with_redis do |redis|
          QUEUES.transform_values do |queue_name|
            redis.llen(queue_name)
          end
        end
      end

      # Checks if a specific queue is full
      # @param queue_key [Symbol] The queue to check
      # @return [Boolean] True if the queue is at or above its maximum size
      def queue_full?(queue_key)
        depths = queue_depths
        depths[queue_key] >= MAX_QUEUE_SIZE[queue_key]
      end

      # Checks if any queues are experiencing backpressure
      # @return [Boolean] True if any queue is at or above its maximum size
      def backpressure?
        queue_depths.any? do |queue_key, depth|
          depth >= MAX_QUEUE_SIZE[queue_key]
        end
      end

      # Processes a batch of raw events
      # Pulls from the raw_events queue and processes each event
      # @param worker_id [String] An identifier for the worker process
      # @return [Integer] The number of raw events processed
      def process_raw_event_batch(worker_id)
        batch = get_next_batch(:raw_events)
        return 0 if batch.empty?

        processed_count = 0

        # Process each raw event in the batch
        batch.each do |item|
          # Get the process_event use case to handle this event
          use_case = UseCaseFactory.create_process_event

          # Call the use case with the raw payload and source
          use_case.call(item[:payload], source: item[:source])

          processed_count += 1
        rescue StandardError => e
          Rails.logger.error("Error processing raw event #{item[:id]}: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))

          # Enqueue to dead-letter queue for failed events
          enqueue_to_dead_letter(item, e)
        end

        processed_count
      end

      # Gets the next batch of items from a queue using an atomic operation
      # @param queue_key [Symbol] The queue to get items from
      # @param count [Integer] The maximum number of items to get
      # @return [Array<Hash>] An array of deserialized job items
      def get_next_batch(queue_key, count = nil)
        batch_size = count || BATCH_SIZE[queue_key]
        queue_name = QUEUES[queue_key]
        processing_queue = "#{queue_name}:processing"
        lock_key = "lock:#{queue_name}"
        lock_timeout = 5 # seconds

        with_redis do |redis|
          # Use a Redis lock to prevent race conditions between workers
          # We use a watch/multi/exec pattern for atomic operations
          acquired = false
          batch = []

          # Try to acquire a lock with timeout
          acquired = redis.set(lock_key, "1", nx: true, ex: lock_timeout)

          if acquired
            begin
              # Atomic operation to move batch from main queue to processing queue
              result = redis.multi do |transaction|
                # Get next batch from queue
                transaction.lrange(queue_name, 0, batch_size - 1)
                # Remove those items from the queue
                transaction.ltrim(queue_name, batch_size, -1)
              end

              # First result is the batch of items
              items = result.first || []

              # Parse and validate the items
              batch = items.map do |item|
                JSON.parse(item, symbolize_names: true)
              rescue JSON::ParserError => e
                Rails.logger.error("Failed to parse queue item: #{e.message}")
                nil
              end.compact
            ensure
              # Release the lock
              redis.del(lock_key)
            end
          else
            # Use debug level for lock contention logging
            Rails.logger.debug { "Worker couldn't acquire lock for #{queue_name}, will try again later" }
          end

          batch
        end
      end

      private

      # Executes a block with a Redis connection from the pool
      def with_redis(&)
        if defined?(REDIS_POOL)
          REDIS_POOL.with(&)
        else
          yield redis
        end
      end

      # Enqueues an item to a dead-letter queue for failed processing
      # @param item [Hash] The original queue item that failed
      # @param error [Exception] The error that caused the failure
      def enqueue_to_dead_letter(item, error)
        with_redis do |redis|
          dead_letter_item = item.merge(
            error: {
              message: error.message,
              backtrace: error.backtrace&.take(10),
              time: Time.current.iso8601
            }
          )

          redis.rpush("queue:dead_letter", dead_letter_item.to_json)
          redis.expire("queue:dead_letter", QUEUE_TTL)
        end
      end

      # Enqueues an item to the specified queue with backpressure handling
      # @param queue_key [Symbol] The queue to add the item to
      # @param item [Hash] The serialized job data
      # @return [Boolean] True if the item was enqueued successfully
      def enqueue_item(queue_key, item)
        queue_name = QUEUES[queue_key]

        with_redis do |redis|
          # Apply backpressure if the queue is too large
          if redis.llen(queue_name) >= MAX_QUEUE_SIZE[queue_key]
            # We have a few strategies for backpressure:
            # 1. Raise an exception (which would result in a 429 Too Many Requests)
            # 2. Drop the item (which would result in data loss)
            # 3. Process older items in the queue to make room

            # For now, we'll use strategy 1 - inform the client of backpressure
            raise QueueBackpressureError, "Queue #{queue_key} is full (max: #{MAX_QUEUE_SIZE[queue_key]})"
          end

          # Add the item to the queue
          redis.multi do |transaction|
            transaction.rpush(queue_name, item.to_json)
            transaction.expire(queue_name, QUEUE_TTL) # Ensure the queue has a TTL
          end
        end

        # Use debug level for routine successful enqueues
        Rails.logger.debug { "Enqueued item to #{queue_key} queue (id: #{item[:id]})" }
        true
      end

      # Serializes an event for storage in Redis
      # @param event [Core::Domain::Event] The event to serialize
      # @return [Hash] A hash representation of the event
      def serialize_event(event)
        {
          id: event.id,
          name: event.name,
          source: event.source,
          timestamp: event.timestamp.iso8601,
          type: "event"
        }
      end

      # Serializes a metric for storage in Redis
      # @param metric [Core::Domain::Metric] The metric to serialize
      # @return [Hash] A hash representation of the metric
      def serialize_metric(metric)
        {
          id: metric.id,
          name: metric.name,
          value: metric.value,
          timestamp: metric.timestamp.iso8601,
          type: "metric"
        }
      end

      # Gets the Redis connection from the cache adapter
      # @return [Redis] A Redis connection
      def redis
        Adapters::Cache::RedisCache.redis
      end

      # Public class for queue backpressure errors
      class QueueBackpressureError < StandardError; end
    end
  end
end
