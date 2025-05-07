# spec/support/hexagonal_helpers.rb

# This module provides support methods for testing Hexagonal Architecture components
module HexagonalHelpers
  # Mock port implementations for testing use cases
  module MockPorts
    # Mock implementation of StoragePort for testing
    class MockStoragePort
      include StoragePort

      attr_reader :saved_events, :saved_metrics, :saved_alerts

      def initialize
        @saved_events = []
        @saved_metrics = []
        @saved_alerts = []
        @events = {}
        @metrics = {}
        @alerts = {}
      end

      def save_event(event)
        # Check if the event has an ID, if not add one
        event_with_id = if event.id.nil?
                          add_id_to_event(event)
                        else
                          event
                        end
        @saved_events << event_with_id
        @events[event_with_id.id] = event_with_id
        event_with_id
      end

      def find_event(id)
        @events[id]
      end

      def save_metric(metric)
        @saved_metrics << metric
        metric_with_id = metric.id.nil? ? add_id_to_metric(metric) : metric
        @metrics[metric_with_id.id] = metric_with_id
        metric_with_id
      end

      def find_metric(id)
        @metrics[id]
      end

      def save_alert(alert)
        @saved_alerts << alert
        alert_with_id = alert.id.nil? ? add_id_to_alert(alert) : alert
        @alerts[alert_with_id.id] = alert_with_id
        alert_with_id
      end

      def find_alert(id)
        @alerts[id]
      end

      def list_metrics(filters = {})
        if filters.empty?
          @metrics.values
        else
          @metrics.values.select do |metric|
            filters.all? do |key, value|
              if metric.dimensions.key?(key)
                metric.dimensions[key] == value
              elsif metric.respond_to?(key)
                metric.send(key) == value
              else
                false
              end
            end
          end
        end
      end

      def list_alerts(filters = {})
        if filters.empty?
          @alerts.values
        else
          @alerts.values.select do |alert|
            filters.all? do |key, value|
              if alert.respond_to?(key)
                alert.send(key) == value
              else
                false
              end
            end
          end
        end
      end

      private

      def add_id_to_event(event)
        Domain::EventFactory.create(
          name: event.name,
          source: event.source,
          timestamp: event.timestamp,
          data: event.data
        )
      end

      def add_id_to_metric(metric)
        Domain::Metric.new(
          id: next_id,
          name: metric.name,
          value: metric.value,
          timestamp: metric.timestamp,
          source: metric.source,
          dimensions: metric.dimensions
        )
      end

      def add_id_to_alert(alert)
        Domain::Alert.new(
          id: next_id,
          name: alert.name,
          severity: alert.severity,
          metric: alert.metric,
          threshold: alert.threshold,
          timestamp: alert.timestamp,
          status: alert.status
        )
      end

      def next_id
        SecureRandom.uuid
      end
    end

    # Mock implementation of CachePort for testing
    class MockCachePort
      include CachePort

      attr_reader :cached_metrics, :metric_history

      def initialize
        @cached_metrics = {}
        @metric_history = {}
      end

      def cache_metric(metric)
        key = cache_key(metric.name, metric.dimensions)
        @cached_metrics[key] = metric

        # Store in time series too
        @metric_history[metric.name] ||= []
        @metric_history[metric.name] << {
          timestamp: metric.timestamp,
          value: metric.value
        }

        # Keep only the latest 1000 values
        @metric_history[metric.name] = @metric_history[metric.name].last(1000)

        metric
      end

      def get_cached_metric(name, dimensions = {})
        key = cache_key(name, dimensions)
        metric = @cached_metrics[key]
        return nil unless metric

        # Return the value, not the whole metric object
        metric.value
      end

      def get_metric_history(name, limit = 100)
        (@metric_history[name] || []).last(limit)
      end

      def clear_metric_cache(name = nil)
        if name.nil?
          @cached_metrics = {}
          @metric_history = {}
        else
          @cached_metrics.delete_if { |key, _| key.start_with?(name) }
          @metric_history.delete(name)
        end
        true
      end

      private

      def cache_key(name, dimensions)
        "#{name}:#{dimensions.sort.map { |k, v| "#{k}=#{v}" }.join('&')}"
      end
    end

    # Mock implementation of NotificationPort for testing
    class MockNotificationPort
      include NotificationPort

      attr_reader :sent_alerts, :sent_messages

      def initialize
        @sent_alerts = []
        @sent_messages = {}
      end

      def send_alert(alert)
        @sent_alerts << alert
        true
      end

      def send_message(channel, message)
        @sent_messages[channel] ||= []
        @sent_messages[channel] << message
        true
      end
    end

    # Mock implementation of QueuePort for testing
    class MockQueuePort
      include QueuePort

      attr_reader :enqueued_events, :enqueued_metrics, :enqueued_raw_events

      def initialize
        @enqueued_events = []
        @enqueued_metrics = []
        @enqueued_raw_events = []
      end

      def enqueue_raw_event(raw_payload, source)
        @enqueued_raw_events << { payload: raw_payload, source: source }
        true
      end

      def enqueue_metric_calculation(event)
        @enqueued_events << event
        true
      end

      def enqueue_anomaly_detection(metric)
        @enqueued_metrics << metric
        true
      end

      def process_raw_event_batch(worker_id)
        count = @enqueued_raw_events.size
        @enqueued_raw_events.clear
        count
      end

      def queue_depths
        {
          raw_events: @enqueued_raw_events.size,
          event_processing: 0,
          metric_calculation: 0,
          anomaly_detection: 0
        }
      end

      def backpressure?
        false
      end

      # Method required for tests
      def with_redis
        # Mock implementation that immediately yields to the block
        yield mock_redis
      end

      private

      def mock_redis
        # Create a simple mock Redis client for testing
        Class.new do
          def llen(key)
            0 # Always return 0 for length
          end

          def lpop(key)
            nil # Always return nil for popping
          end

          def keys(pattern)
            [] # Always return empty array for keys
          end

          def exists?(key)
            false # Always return false for exists?
          end
        end.new
      end
    end
  end

  # Helper methods for setting up test dependencies
  module Dependencies
    def setup_test_container
      DependencyContainer.reset

      # Register mock ports for testing
      DependencyContainer.register(
        :storage_port,
        HexagonalHelpers::MockPorts::MockStoragePort.new
      )

      DependencyContainer.register(
        :cache_port,
        HexagonalHelpers::MockPorts::MockCachePort.new
      )

      DependencyContainer.register(
        :notification_port,
        HexagonalHelpers::MockPorts::MockNotificationPort.new
      )

      DependencyContainer.register(
        :queue_port,
        HexagonalHelpers::MockPorts::MockQueuePort.new
      )
    end

    def storage_port
      DependencyContainer.resolve(:storage_port)
    end

    def cache_port
      DependencyContainer.resolve(:cache_port)
    end

    def notification_port
      DependencyContainer.resolve(:notification_port)
    end

    def queue_port
      DependencyContainer.resolve(:queue_port)
    end
  end
end

RSpec.configure do |config|
  config.include HexagonalHelpers::Dependencies

  config.before do
    setup_test_container
  end
end

# Autoload the Core, Ports, and Adapters modules for testing
# This ensures that all the modules are available in test environment

# This is needed because Rails' auto-loading in test environment
# may not load all modules until they are referenced

# Make sure Core modules are loaded
module Core
  module Domain; end
  module UseCases; end
end

# Make sure Ports are loaded
module Ports; end

# Make sure Adapters are loaded
module Adapters
  module Repositories; end
  module Cache; end
  module Notifications; end
  module Queue; end
  module Web; end
end
