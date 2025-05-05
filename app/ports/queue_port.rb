module QueuePort
  # Enqueues a raw webhook payload for asynchronous processing
  # @param raw_payload [String] The raw JSON webhook payload
  # @param source [String] The source system (github, jira, gitlab, etc.)
  # @return [Boolean] True if the job was enqueued successfully
  def enqueue_raw_event(raw_payload, source)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Enqueues a domain event for metric calculation
  # @param event [Domain::Event] The event to process
  # @return [Boolean] True if the job was enqueued successfully
  def enqueue_metric_calculation(event)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Enqueues a metric for anomaly detection
  # @param metric [Domain::Metric] The metric to analyze
  # @return [Boolean] True if the job was enqueued successfully
  def enqueue_anomaly_detection(metric)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Processes the next batch of raw events
  # @param worker_id [String] An identifier for the worker process
  # @return [Integer] The number of events processed
  def process_raw_event_batch(worker_id)
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Gets current queue depths
  # @return [Hash] A hash of queue names and their current size
  def queue_depths
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end

  # Checks if any queues are experiencing backpressure
  # @return [Boolean] True if any queue is at or above its maximum size
  def backpressure?
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end
end
