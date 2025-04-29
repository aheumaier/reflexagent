# frozen_string_literal: true

# DependencyContainer provides a simple dependency injection mechanism
# for wiring ports to adapters in our Hexagonal Architecture
class DependencyContainer
  class << self
    def register(port, adapter)
      adapters[port] = adapter
    end

    def resolve(port)
      adapters[port] or raise "No adapter registered for port: #{port}"
    end

    def reset
      @adapters = {}
    end

    private

    def adapters
      @adapters ||= {}
    end
  end
end

# Use case factory - creates use cases with their dependencies injected
class UseCaseFactory
  class << self
    def create_process_event
      Core::UseCases::ProcessEvent.new(
        storage_port: DependencyContainer.resolve(:storage_port),
        queue_port: DependencyContainer.resolve(:queue_port)
      )
    end

    def create_calculate_metrics
      Core::UseCases::CalculateMetrics.new(
        storage_port: DependencyContainer.resolve(:storage_port),
        cache_port: DependencyContainer.resolve(:cache_port)
      )
    end

    def create_detect_anomalies
      Core::UseCases::DetectAnomalies.new(
        storage_port: DependencyContainer.resolve(:storage_port),
        notification_port: DependencyContainer.resolve(:notification_port)
      )
    end

    def create_send_notification
      Core::UseCases::SendNotification.new(
        notification_port: DependencyContainer.resolve(:notification_port),
        storage_port: DependencyContainer.resolve(:storage_port)
      )
    end
  end
end

# Register adapters in an initializer that runs after Rails is fully loaded
Rails.application.config.after_initialize do
  # Skip wiring in test environment - tests will explicitly set up their dependencies
  unless Rails.env.test?
    # Register ports to adapters in production/development
    if defined?(Adapters)
      # Storage port implementation
      DependencyContainer.register(
        :storage_port,
        Adapters::Repositories::EventRepository.new
      )

      # Cache port implementation
      DependencyContainer.register(
        :cache_port,
        Adapters::Cache::RedisCache.new
      )

      # Notification port implementation
      DependencyContainer.register(
        :notification_port,
        Adapters::Notifications::SlackNotifier.new
      )

      # Queue port implementation
      DependencyContainer.register(
        :queue_port,
        Adapters::Queue::ProcessEventWorker.new
      )

      # Dashboard port implementation
      DependencyContainer.register(
        :dashboard_port,
        Adapters::Web::DashboardController.new # This won't be used directly
      )
    end
  end
end
