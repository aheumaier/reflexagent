# frozen_string_literal: true

module Adapters
  module Queue
    class RedisQueue
      # Default queue name
      DEFAULT_QUEUE = "default"

      # Default TTL for queue items (12 hours)
      DEFAULT_TTL = 43_200

      # Default retry count
      DEFAULT_MAX_RETRIES = 3

      # Default batch size
      DEFAULT_BATCH_SIZE = 100

      # Default dead letter queue suffix
      DLQ_SUFFIX = "_dlq"

      # Enqueue an item in the specified queue
      # @param item [Object] The item to enqueue (will be JSON serialized)
      # @param queue_name [String] The name of the queue
      # @param ttl [Integer] Time to live in seconds
      # @return [Boolean] true if successful
      def enqueue(item, queue_name: DEFAULT_QUEUE, ttl: DEFAULT_TTL)
        Adapters::Cache::RedisManager.with_redis(:queue) do |redis|
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
        Adapters::Cache::RedisManager.with_redis(:queue) do |redis|
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
        Adapters::Cache::RedisManager.with_redis(:queue) do |redis|
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
        Adapters::Cache::RedisManager.with_redis(:queue) do |redis|
          redis.llen(queue_key(queue_name))
        end
      rescue Redis::BaseError => e
        Rails.logger.error("Redis queue size error: #{e.message}")
        0
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

      # Flush all items from a queue
      # @param queue_name [String] The name of the queue
      # @return [Integer] The number of items removed
      def flush(queue_name: DEFAULT_QUEUE)
        Adapters::Cache::RedisManager.with_redis(:queue) do |redis|
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
      def batch_process(queue_name: DEFAULT_QUEUE, batch_size: DEFAULT_BATCH_SIZE, ttl: 600, &block)
        return 0 unless block_given?

        batch = []
        processed = 0

        Adapters::Cache::RedisManager.with_redis(:queue) do |redis|
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

      # Get the full queue key with namespace
      def queue_key(queue_name)
        "queue:#{Rails.env}:#{queue_name}"
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
    end
  end
end
