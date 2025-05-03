# frozen_string_literal: true

# DependencyContainer provides a simple dependency injection mechanism
# for wiring ports to adapters in our Hexagonal Architecture
class DependencyContainer
  class << self
    def register(port, adapter)
      Rails.logger.info { "Registering adapter for port: #{port} with #{adapter.class.name}" }
      adapters[port] = adapter
    end

    def resolve(port)
      Rails.logger.info { "Resolving adapter for port: #{port} (available: #{adapters.keys.inspect})" }
      adapters[port] or raise "No adapter registered for port: #{port}"
    end

    def reset
      @adapters = {}
    end

    # Expose adapters for debugging
    def adapters
      @adapters ||= {}
    end
  end
end

# Register dependencies adapters in an initializer that runs after Rails is fully loaded
Rails.application.config.after_initialize do
  Rails.logger.info "Initializing dependency injection..."

  # Let's initialize the adapters on startup
  begin
    # Load domain models first
    require_relative "../../app/core/domain/event"
    require_relative "../../app/core/domain/alert"
    require_relative "../../app/core/domain/metric"
    require_relative "../../app/core/domain/actuator"
    require_relative "../../app/core/domain/reflexive_agent"
    require_relative "../../app/core/domain/metric_classifier"

    # Not - need in eager loading Load ALL ports before ANY adapters
    require_relative "../../app/ports/ingestion_port"
    require_relative "../../app/ports/storage_port"
    require_relative "../../app/ports/cache_port"
    require_relative "../../app/ports/queue_port"
    require_relative "../../app/ports/notification_port"

    # Only after ALL ports are loaded, load adapter classes
    require_relative "../../app/adapters/web/web_adapter"
    require_relative "../../app/adapters/repositories/event_repository"
    require_relative "../../app/adapters/repositories/metric_repository"
    require_relative "../../app/adapters/repositories/alert_repository"
    require_relative "../../app/adapters/cache/redis_cache"
    require_relative "../../app/adapters/notifications/slack_notifier"
    require_relative "../../app/adapters/notifications/email_notifier"
    require_relative "../../app/adapters/queuing/sidekiq_queue_adapter"

    # Now register them
    Rails.logger.info "Registering adapters..."

    # Ingestion port implementation
    DependencyContainer.register(
      :ingestion_port,
      Web::WebAdapter.new
    )

    # Register domain-specific repositories directly
    # Each repository is now explicitly used by the appropriate use cases
    DependencyContainer.register(
      :event_repository,
      Repositories::EventRepository.new
    )
    DependencyContainer.register(
      :metric_repository,
      Repositories::MetricRepository.new
    )
    DependencyContainer.register(
      :alert_repository,
      Repositories::AlertRepository.new
    )

    # Cache port implementation
    DependencyContainer.register(
      :cache_port,
      Cache::RedisCache.new
    )

    # Queue port implementation
    DependencyContainer.register(
      :queue_port,
      Queuing::SidekiqQueueAdapter.new
    )

    # Notification port implementation
    DependencyContainer.register(
      :notification_port,
      Notifications::EmailNotifier.new
    )

    # Register the MetricClassifier as a service
    DependencyContainer.register(
      :metric_classifier,
      Domain::MetricClassifier.new
    )

    Rails.logger.info "Dependency injection initialized with ports: #{DependencyContainer.adapters.keys.inspect}"
  rescue StandardError => e
    Rails.logger.error "Error initializing dependency injection: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e if Rails.env.local?
  end
end
