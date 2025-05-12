require_relative "use_cases/process_event"
require_relative "use_cases/calculate_metrics"
require_relative "use_cases/detect_anomalies"
require_relative "use_cases/send_notification"
require_relative "use_cases/find_event"
require_relative "use_cases/find_metric"
require_relative "use_cases/find_alert"
require_relative "use_cases/list_metrics"
require_relative "use_cases/list_alerts"
require_relative "use_cases/analyze_commits"
require_relative "use_cases/dashboard_metrics"
require_relative "use_cases/register_repository"
require_relative "use_cases/list_team_repositories"
require_relative "use_cases/find_or_create_team"
require_relative "use_cases/analyze_team_performance"

class UseCaseFactory
  class << self
    def create_process_event
      UseCases::ProcessEvent.new(
        ingestion_port: DependencyContainer.resolve(:ingestion_port),
        storage_port: DependencyContainer.resolve(:event_repository),
        queue_port: DependencyContainer.resolve(:queue_port),
        team_repository_port: DependencyContainer.resolve(:team_repository),
        logger_port: Rails.logger
      )
    end

    def create_calculate_metrics
      # CalculateMetrics needs both repositories - it finds events but saves metrics
      # Create a temporary composite adapter for backward compatibility
      composite_repository = Object.new

      # Add event repository methods
      event_repository = DependencyContainer.resolve(:event_repository)
      metric_repository = DependencyContainer.resolve(:metric_repository)

      # Define methods on our anonymous composite object
      composite_repository.define_singleton_method(:find_event) do |id|
        event_repository.find_event(id)
      end

      # Add metric repository methods
      [:save_metric, :find_metric, :find_aggregate_metric, :update_metric].each do |method|
        composite_repository.define_singleton_method(method) do |*args|
          metric_repository.send(method, *args)
        end
      end

      UseCases::CalculateMetrics.new(
        storage_port: composite_repository,
        cache_port: DependencyContainer.resolve(:cache_port),
        metric_classifier: DependencyContainer.resolve(:metric_classifier),
        dimension_extractor: DependencyContainer.resolve(:dimension_extractor),
        team_repository_port: DependencyContainer.resolve(:team_repository)
      )
    end

    def create_detect_anomalies
      UseCases::DetectAnomalies.new(
        storage_port: DependencyContainer.resolve(:metric_repository),
        notification_port: DependencyContainer.resolve(:notification_port)
      )
    end

    def create_send_notification
      UseCases::SendNotification.new(
        storage_port: DependencyContainer.resolve(:alert_repository),
        notification_port: DependencyContainer.resolve(:notification_port)
      )
    end

    def create_find_event
      UseCases::FindEvent.new(
        storage_port: DependencyContainer.resolve(:event_repository)
      )
    end

    def create_find_metric
      UseCases::FindMetric.new(
        storage_port: DependencyContainer.resolve(:metric_repository)
      )
    end

    def create_find_alert
      UseCases::FindAlert.new(
        storage_port: DependencyContainer.resolve(:alert_repository)
      )
    end

    def create_list_metrics
      UseCases::ListMetrics.new(
        storage_port: DependencyContainer.resolve(:metric_repository)
      )
    end

    def create_list_alerts
      UseCases::ListAlerts.new(
        storage_port: DependencyContainer.resolve(:alert_repository)
      )
    end

    def create_analyze_commits
      UseCases::AnalyzeCommits.new(
        storage_port: DependencyContainer.resolve(:metric_repository),
        cache_port: DependencyContainer.resolve(:cache_port),
        dimension_extractor: DependencyContainer.resolve(:dimension_extractor)
      )
    end

    def create_dashboard_metrics
      UseCases::DashboardMetrics.new(
        storage_port: DependencyContainer.resolve(:metric_repository),
        cache_port: DependencyContainer.resolve(:cache_port)
      )
    end

    def create_register_repository
      UseCases::RegisterRepository.new(
        team_repository_port: DependencyContainer.resolve(:team_repository),
        logger_port: Rails.logger
      )
    end

    def create_list_team_repositories
      UseCases::ListTeamRepositories.new(
        team_repository_port: DependencyContainer.resolve(:team_repository),
        cache_port: DependencyContainer.resolve(:cache_port),
        logger_port: Rails.logger
      )
    end

    def create_find_or_create_team
      UseCases::FindOrCreateTeam.new(
        team_repository_port: DependencyContainer.resolve(:team_repository),
        logger_port: Rails.logger
      )
    end

    def create_analyze_team_performance
      UseCases::AnalyzeTeamPerformance.new(
        issue_metric_repository: DependencyContainer.resolve(:issue_metric_repository),
        storage_port: DependencyContainer.resolve(:metric_repository),
        cache_port: DependencyContainer.resolve(:cache_port),
        logger_port: Rails.logger
      )
    end
  end
end
