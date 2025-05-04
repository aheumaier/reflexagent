# frozen_string_literal: true

require "sidekiq"
require "sidekiq-scheduler"

# Disable strict argument checking
# This is a backup safety measure in case the string conversion elsewhere fails
Sidekiq.strict_args!(false)

# Make sure Core module is defined for Sidekiq workers
module Core
  module UseCases
  end
end

# Calculate Redis connection pools based on available connections (Render Free tier: 50 max connections)
# Reserve ~10 connections for other app needs, leaving 40 for Sidekiq
sidekiq_concurrency = ENV.fetch("SIDEKIQ_CONCURRENCY", 2).to_i
# Reserve 2 connections per worker thread, plus a few for scheduler
server_redis_size = [sidekiq_concurrency + 2, 4].min
# Reserve fewer connections for client operations
client_redis_size = [3, 4].min

# Configure Sidekiq
Sidekiq.configure_server do |config|
  # Set Redis connection
  redis_url = ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" }

  config.redis = {
    url: redis_url,
    size: ENV.fetch("SIDEKIQ_REDIS_POOL_SIZE", server_redis_size).to_i,
    network_timeout: ENV.fetch("REDIS_TIMEOUT", 5).to_i,
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  }

  # Configure Sidekiq logging
  config.logger.level = Rails.logger.level

  # Make sure all core modules are required for workers
  config.on(:startup) do
    # Load domain models
    require_relative "../../app/core/domain/event"
    require_relative "../../app/core/domain/alert"
    require_relative "../../app/core/domain/metric"

    # Load the use case classes
    require_relative "../../app/core/use_cases/process_event"
    require_relative "../../app/core/use_cases/calculate_metrics"
    require_relative "../../app/core/use_cases/detect_anomalies"
    require_relative "../../app/core/use_cases/send_notification"

    # If the UseCases module is defined but not inside Core, alias it
    Core::UseCases = UseCases if defined?(UseCases) && !defined?(Core::UseCases)
  end

  # Configure the scheduler
  config.on(:startup) do
    Sidekiq.schedule = {
      "metric_aggregation_5min" => {
        "class" => "MetricAggregationJob",
        "cron" => "*/5 * * * *",  # Every 5 minutes
        "args" => ["5min"],
        "queue" => "metric_aggregation"
      },
      "metric_aggregation_hourly" => {
        "class" => "MetricAggregationJob",
        "cron" => "0 * * * *",    # Every hour
        "args" => ["hourly"],
        "queue" => "metric_aggregation"
      },
      "metric_aggregation_daily" => {
        "class" => "MetricAggregationJob",
        "cron" => "0 0 * * *",    # Daily at midnight
        "args" => ["daily"],
        "queue" => "metric_aggregation"
      }
    }

    SidekiqScheduler::Scheduler.instance.reload_schedule!
  end
end

Sidekiq.configure_client do |config|
  # Set Redis connection for client
  redis_url = ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" }

  config.redis = {
    url: redis_url,
    size: ENV.fetch("SIDEKIQ_CLIENT_REDIS_POOL_SIZE", client_redis_size).to_i,
    network_timeout: ENV.fetch("REDIS_TIMEOUT", 5).to_i,
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  }
end

# Default queue options
Sidekiq.default_job_options = {
  "backtrace" => true,
  "retry" => 3
}

# Log Sidekiq initialization with connection pool sizes
Rails.logger.info "Sidekiq initialized with Redis URL: #{ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')}"
Rails.logger.info "Server Redis pool size: #{ENV.fetch('SIDEKIQ_REDIS_POOL_SIZE', server_redis_size)}"
Rails.logger.info "Client Redis pool size: #{ENV.fetch('SIDEKIQ_CLIENT_REDIS_POOL_SIZE', client_redis_size)}"
