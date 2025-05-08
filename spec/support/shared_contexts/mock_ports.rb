# frozen_string_literal: true

# Shared context that provides mock implementations of all ports for testing
RSpec.shared_context "with all mock ports" do
  let(:mock_ingestion_port) do
    double("MockIngestionPort").tap do |mock|
      allow(mock).to receive(:receive_event)
    end
  end

  let(:mock_storage_port) do
    double("MockStoragePort").tap do |mock|
      allow(mock).to receive(:save_event)
      allow(mock).to receive(:find_event)
      allow(mock).to receive(:save_metric)
      allow(mock).to receive(:find_metric)
      allow(mock).to receive(:find_aggregate_metric)
      allow(mock).to receive(:update_metric)
      allow(mock).to receive(:list_metrics)
      allow(mock).to receive(:list_events)
      allow(mock).to receive(:save_alert)
      allow(mock).to receive(:find_alert)
      allow(mock).to receive(:list_alerts)
    end
  end

  let(:mock_queue_port) do
    double("MockQueuePort").tap do |mock|
      allow(mock).to receive(:enqueue_metric_calculation)
      allow(mock).to receive(:enqueue_job)
    end
  end

  let(:mock_notification_port) do
    double("MockNotificationPort").tap do |mock|
      allow(mock).to receive(:send_notification)
      allow(mock).to receive(:sent_alerts).and_return([])
      allow(mock).to receive(:send_alert)
    end
  end

  let(:mock_cache_port) do
    double("MockCachePort").tap do |mock|
      allow(mock).to receive(:get)
      allow(mock).to receive(:set)
      allow(mock).to receive(:delete)
      allow(mock).to receive(:cached_metrics).and_return([])
      allow(mock).to receive(:cache_metric)
      allow(mock).to receive(:write)
    end
  end

  let(:mock_team_repository_port) do
    double("MockTeamRepositoryPort").tap do |mock|
      allow(mock).to receive(:save_team)
      allow(mock).to receive(:find_team)
      allow(mock).to receive(:find_team_by_slug)
      allow(mock).to receive(:list_teams)
      allow(mock).to receive(:save_repository)
      allow(mock).to receive(:find_repository)
      allow(mock).to receive(:find_repository_by_name)
      allow(mock).to receive(:list_repositories)
      allow(mock).to receive(:list_repositories_for_team)
      allow(mock).to receive(:find_team_for_repository)
      allow(mock).to receive(:associate_repository_with_team)
    end
  end

  let(:mock_logger_port) do
    double("MockLoggerPort").tap do |mock|
      allow(mock).to receive(:debug)
      allow(mock).to receive(:info)
      allow(mock).to receive(:warn)
      allow(mock).to receive(:error)
    end
  end
end
