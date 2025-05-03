# frozen_string_literal: true

class ServiceFactory
  class << self
    def create_metrics_service
      MetricsService.new(
        storage_port: Repositories::MetricRepository.new,
        cache_port: Cache::RedisCache.new
      )
    end

    def create_dora_service
      DoraService.new(
        storage_port: Repositories::MetricRepository.new
      )
    end

    def create_alert_service
      AlertService.new(
        storage_port: Repositories::AlertRepository.new
      )
    end
  end
end
