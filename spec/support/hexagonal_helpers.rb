# spec/support/hexagonal_helpers.rb

# This module provides support methods for testing Hexagonal Architecture components
module HexagonalHelpers
  # Mock port implementations for testing use cases
  module MockPorts
    # Mock implementation of StoragePort for testing
    class MockStoragePort
      include Ports::StoragePort

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
      include Ports::CachePort

      attr_reader :cached_metrics

      def initialize
        @cached_metrics = {}
      end

      def cache_metric(metric)
        key = cache_key(metric.name, metric.dimensions)
        @cached_metrics[key] = metric
        metric
      end

      def get_cached_metric(name, dimensions = {})
        key = cache_key(name, dimensions)
        @cached_metrics[key]
      end

      def clear_metric_cache(name = nil)
        if name.nil?
          @cached_metrics = {}
        else
          @cached_metrics.delete_if { |key, _| key.start_with?(name) }
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
      include Ports::NotificationPort

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
      include Ports::QueuePort

      attr_reader :enqueued_events, :enqueued_metrics

      def initialize
        @enqueued_events = []
        @enqueued_metrics = []
      end

      def enqueue_metric_calculation(event)
        @enqueued_events << event
        true
      end

      def enqueue_anomaly_detection(metric)
        @enqueued_metrics << metric
        true
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
