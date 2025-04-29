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
        storage_port: DependencyContainer.resolve(:storage_port),
        notification_port: DependencyContainer.resolve(:notification_port)
      )
    end

    def create_find_event
      Core::UseCases::FindEvent.new(
        storage_port: DependencyContainer.resolve(:storage_port)
      )
    end

    def create_find_metric
      Core::UseCases::FindMetric.new(
        storage_port: DependencyContainer.resolve(:storage_port)
      )
    end

    def create_find_alert
      Core::UseCases::FindAlert.new(
        storage_port: DependencyContainer.resolve(:storage_port)
      )
    end

    def create_list_metrics
      Core::UseCases::ListMetrics.new(
        storage_port: DependencyContainer.resolve(:storage_port)
      )
    end

    def create_list_alerts
      Core::UseCases::ListAlerts.new(
        storage_port: DependencyContainer.resolve(:storage_port)
      )
    end
  end
end
