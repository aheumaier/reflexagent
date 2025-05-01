module Adapters
  module Queue
    class RedisQueueAdapter
      include Ports::QueuePort

      # Default queue name
      DEFAULT_QUEUE = "default"

      # Default TTL for queue items (3 days)
      DEFAULT_TTL = 3 * 24 * 60 * 60

      # Default retry count
      DEFAULT_MAX_RETRIES = 3

      # Default dead letter queue suffix
      DLQ_SUFFIX = "_dlq"

      # Queue configuration for the application
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
      # @param event [Core::Domain::Event] The event to process
      # @return [Boolean] True if the job was enqueued successfully
      def enqueue_metric_calculation(event)
        event_data = serialize_event(event)
        enqueue_item(:metric_calculation, event_data)
        Rails.logger.debug { "Enqueued metric calculation job for event: #{event.id}" }
        true
      rescue StandardError => e
        Rails.logger.error("Failed to enqueue metric calculation: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        false
      end

      # Enqueues a job to process an event
      # @param event [Core::Domain::Event] The event to process
      # @return [Boolean] True if the job was enqueued successfully
      def enqueue_event_processing(event)
        enqueue_item(:event_processing, serialize_event(event))
        Rails.logger.debug { "Enqueued event processing job for event: #{event.id}" }
        true
      rescue StandardError => e
        Rails.logger.error("Failed to enqueue event processing: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        false
      end

      # Enqueues a job to process anomaly detection for a metric
      # @param metric [Core::Domain::Metric] The metric to analyze
      # @return [Boolean] True if the job was enqueued successfully
      def enqueue_anomaly_detection(metric)
        metric_data = serialize_metric(metric)
        enqueue_item(:anomaly_detection, metric_data)
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

      # Enqueue an item in the specified queue
      # @param item [Object] The item to enqueue (will be JSON serialized)
      # @param queue_name [String] The name of the queue
      # @param ttl [Integer] Time to live in seconds
      # @return [Boolean] true if successful
      def enqueue(item, queue_name: DEFAULT_QUEUE, ttl: DEFAULT_TTL)
        with_redis do |redis|
          key = queue_key(queue_name)

          # Serialize the item for storage
          serialized_item = serialize_item(item)

          # Use RPUSH to add to the right side of the list (FIFO order)
          redis.rpush(key, serialized_item)

          # Set expiration on the queue if TTL is provided
          redis.expire(key, ttl) if ttl.positive?
        end

        true
      rescue Redis::BaseError => e
        Rails.logger.error("Redis queue enqueue error: #{e.message}")
        false
      end

      # Dequeue an item from the specified queue
      # @param queue_name [String] The name of the queue
      # @param block [Boolean] Whether to block until an item is available
      # @param timeout [Integer] Timeout in seconds for blocking operation
      # @return [Object, nil] The dequeued item or nil if none available
      def dequeue(queue_name: DEFAULT_QUEUE, block: false, timeout: 1)
        with_redis do |redis|
          key = queue_key(queue_name)

          # If blocking is requested, use BLPOP
          if block
            result = redis.blpop(key, timeout: timeout)
            return nil unless result

            # BLPOP returns [key, value]
            deserialize_item(result[1])
          else
            # Use LPOP to remove from the left side of the list (FIFO order)
            item = redis.lpop(key)
            return nil unless item

            deserialize_item(item)
          end
        end
      rescue Redis::BaseError => e
        Rails.logger.error("Redis queue dequeue error: #{e.message}")
        nil
      end

      # Peek at the next item without removing it
      # @param queue_name [String] The name of the queue
      # @return [Object, nil] The next item or nil if none available
      def peek(queue_name: DEFAULT_QUEUE)
        with_redis do |redis|
          key = queue_key(queue_name)

          # Use LINDEX to get the first item without removing it
          item = redis.lindex(key, 0)
          return nil unless item

          deserialize_item(item)
        end
      rescue Redis::BaseError => e
        Rails.logger.error("Redis queue peek error: #{e.message}")
        nil
      end

      # Get the queue length
      # @param queue_name [String] The name of the queue
      # @return [Integer] The number of items in the queue
      def size(queue_name: DEFAULT_QUEUE)
        with_redis do |redis|
          redis.llen(queue_key(queue_name))
        end
      rescue Redis::BaseError => e
        Rails.logger.error("Redis queue size error: #{e.message}")
        0
      end

      # Flush all items from a queue
      # @param queue_name [String] The name of the queue
      # @return [Integer] The number of items removed
      def flush(queue_name: DEFAULT_QUEUE)
        with_redis do |redis|
          key = queue_key(queue_name)
          count = redis.llen(key)
          redis.del(key)
          count
        end
      rescue Redis::BaseError => e
        Rails.logger.error("Redis queue flush error: #{e.message}")
        0
      end

      # Batch process items from a queue with backpressure control
      # @param queue_name [String] The name of the queue
      # @param batch_size [Integer] Maximum number of items to process at once
      # @param ttl [Integer] Time to live for processing lock
      # @yield [items] The batch of items to process
      # @return [Integer] The number of items processed
      def batch_process(queue_name: DEFAULT_QUEUE, batch_size: BATCH_SIZE[:raw_events], ttl: 600, &block)
        return 0 unless block_given?

        batch = []
        processed = 0

        with_redis do |redis|
          # Get a processing lock with TTL to avoid multiple workers processing the same batch
          lock_key = "#{queue_key(queue_name)}:processing_lock"
          return 0 unless redis.set(lock_key, 1, nx: true, ex: ttl)

          # Move items to a temporary processing queue
          processing_key = "#{queue_key(queue_name)}:processing"

          # Get batch size items from main queue to processing queue
          batch_size.times do
            item = redis.lpop(queue_key(queue_name))
            break unless item

            redis.rpush(processing_key, item)
            batch << deserialize_item(item)
          end

          # Process the batch if we got any items
          unless batch.empty?
            begin
              yield(batch)
              processed = batch.size

              # Remove the processing queue after successful processing
              redis.del(processing_key)
            rescue StandardError => e
              # Move items back to the main queue on error
              while (item = redis.lpop(processing_key))
                redis.rpush(queue_key(queue_name), item)
              end

              Rails.logger.error("Batch processing error: #{e.message}")
              raise
            end
          end

          # Release the lock explicitly
          redis.del(lock_key)
        end

        processed
      rescue Redis::BaseError => e
        Rails.logger.error("Redis batch processing error: #{e.message}")
        0
      end

      private

      # Executes a block with a Redis connection from the pool
      def with_redis(&)
        if defined?(REDIS_POOL)
          REDIS_POOL.with(&)
        else
          Adapters::Cache::RedisManager.with_redis(:queue, &)
        end
      end

      # Get the full queue key with namespace
      def queue_key(queue_name)
        if QUEUES.values.include?(queue_name)
          queue_name
        else
          "queue:#{Rails.env}:#{queue_name}"
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
          redis.expire("queue:dead_letter", DEFAULT_TTL)
        end
      end

      # Move a failed item to the dead letter queue
      # @param item [Object] The failed item
      # @param queue_name [String] The original queue name
      # @param error [Exception] The error that caused the failure
      # @return [Boolean] true if successful
      def move_to_dlq(item, queue_name: DEFAULT_QUEUE, error: nil)
        dlq_name = "#{queue_name}#{DLQ_SUFFIX}"

        # Add error information to the item
        dlq_item = {
          original_item: item,
          error: error&.message,
          backtrace: error&.backtrace&.first(10),
          failed_at: Time.current
        }

        enqueue(dlq_item, queue_name: dlq_name)
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
            transaction.expire(queue_name, DEFAULT_TTL) # Ensure the queue has a TTL
          end
        end

        # Use debug level for routine successful enqueues
        Rails.logger.debug { "Enqueued item to #{queue_key} queue (id: #{item[:id]})" }
        true
      end

      # Serialize an item for storage
      def serialize_item(item)
        JSON.generate(item)
      rescue StandardError => e
        Rails.logger.error("Queue item serialization error: #{e.message}")
        JSON.generate({ error: "Serialization failed", original_class: item.class.name })
      end

      # Deserialize an item from storage
      def deserialize_item(serialized_item)
        JSON.parse(serialized_item, symbolize_names: true)
      rescue StandardError => e
        Rails.logger.error("Queue item deserialization error: #{e.message}")
        { error: "Deserialization failed", raw_data: serialized_item }
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

      # Public class for queue backpressure errors
      class QueueBackpressureError < StandardError; end
    end
  end
end
