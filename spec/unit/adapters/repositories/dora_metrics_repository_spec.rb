# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repositories::DoraMetricsRepository do
  let(:metric_naming_port) { double("MetricNamingPort") }
  let(:logger_port) { double("LoggerPort", debug: nil, info: nil, warn: nil, error: nil) }
  let(:repository) { described_class.new(metric_naming_port: metric_naming_port, logger_port: logger_port) }

  # Shared test data
  let(:start_time) { 30.days.ago }
  let(:end_time) { Time.current }
  let(:team_id) { "team-123" }
  let(:repository_name) { "test-org/test-repo" }
  let(:service_name) { "test-service" }

  describe "#deployment_frequency" do
    let(:github_deployments) do
      [
        double("Metric", timestamp: start_time + 1.day, value: 1.0),
        double("Metric", timestamp: start_time + 2.days, value: 1.0),
        double("Metric", timestamp: end_time - 1.day, value: 1.0)
      ]
    end

    it "calculates deployment frequency for a team/project" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.deployment.completed", {}, start_time)
        .and_return(github_deployments)

      # Act
      result = repository.deployment_frequency(start_time: start_time, end_time: end_time)

      # Assert
      expect(result).to be_a(Hash)
      expect(result[:deployment_count]).to eq(3)
      expect(result[:frequency_per_day]).to be_a(Float)
      expect(result[:frequency_per_week]).to be_a(Float)
      expect(result[:performance_level]).to be_a(String)
    end

    it "applies team filter if provided" do
      # Arrange
      expect(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.deployment.completed", { team_id: team_id }, start_time)
        .and_return(github_deployments)

      # Act
      repository.deployment_frequency(start_time: start_time, end_time: end_time, team_id: team_id)

      # Assert - verification is in the expect().to receive() call above
    end

    it "applies repository filter if provided" do
      # Arrange
      expect(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.deployment.completed", { repository: repository_name }, start_time)
        .and_return(github_deployments)

      # Act
      repository.deployment_frequency(start_time: start_time, end_time: end_time, repository: repository_name)

      # Assert - verification is in the expect().to receive() call above
    end

    it "applies time range filters" do
      # Arrange - create metrics where one is after the end_time
      metrics = [
        double("Metric", timestamp: start_time + 1.day, value: 1.0),  # Inside range
        double("Metric", timestamp: end_time + 1.day, value: 1.0)     # Outside range (after end_time)
      ]

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.deployment.completed", {}, start_time)
        .and_return(metrics)

      # Act
      result = repository.deployment_frequency(start_time: start_time, end_time: end_time)

      # Assert
      expect(result[:deployment_count]).to eq(1) # Only one deployment is within the time range
    end

    it "includes frequency label in results" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.deployment.completed", {}, start_time)
        .and_return(github_deployments)

      # We'll test each performance level
      allow(repository).to receive(:deployment_frequency_label).and_return("elite")

      # Act
      result = repository.deployment_frequency(start_time: start_time, end_time: end_time)

      # Assert
      expect(result[:performance_level]).to eq("elite")
    end
  end

  describe "#lead_time_for_changes" do
    let(:github_lead_times) do
      [
        double("Metric", timestamp: start_time + 1.day, value: 12.0),  # 12 hours
        double("Metric", timestamp: start_time + 2.days, value: 24.0), # 24 hours
        double("Metric", timestamp: end_time - 1.day, value: 36.0)     # 36 hours
      ]
    end

    it "calculates lead time for changes for a team/project" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.ci.lead_time", {}, start_time)
        .and_return(github_lead_times)

      # Act
      result = repository.lead_time_for_changes(start_time: start_time, end_time: end_time)

      # Assert
      expect(result).to be_a(Hash)
      expect(result[:change_count]).to eq(3)
      expect(result[:average_lead_time_hours]).to eq(24.0)
      expect(result[:median_lead_time_hours]).to eq(24.0)
      expect(result[:p90_lead_time_hours]).to eq(36.0)
      expect(result[:performance_level]).to be_a(String)
    end

    it "applies team filter if provided" do
      # Arrange
      expect(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.ci.lead_time", { team_id: team_id }, start_time)
        .and_return(github_lead_times)

      # Act
      repository.lead_time_for_changes(start_time: start_time, end_time: end_time, team_id: team_id)

      # Assert - verification is in the expect().to receive() call above
    end

    it "applies repository filter if provided" do
      # Arrange
      expect(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.ci.lead_time", { repository: repository_name }, start_time)
        .and_return(github_lead_times)

      # Act
      repository.lead_time_for_changes(start_time: start_time, end_time: end_time, repository: repository_name)

      # Assert - verification is in the expect().to receive() call above
    end

    it "applies time range filters" do
      # Arrange - create metrics where one is after the end_time
      metrics = [
        double("Metric", timestamp: start_time + 1.day, value: 24.0),  # Inside range
        double("Metric", timestamp: end_time + 1.day, value: 36.0)     # Outside range (after end_time)
      ]

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.ci.lead_time", {}, start_time)
        .and_return(metrics)

      # Act
      result = repository.lead_time_for_changes(start_time: start_time, end_time: end_time)

      # Assert
      expect(result[:change_count]).to eq(1) # Only one metric is within the time range
    end

    it "includes performance label in results" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.ci.lead_time", {}, start_time)
        .and_return(github_lead_times)

      # We'll test each performance level
      allow(repository).to receive(:lead_time_label).and_return("high")

      # Act
      result = repository.lead_time_for_changes(start_time: start_time, end_time: end_time)

      # Assert
      expect(result[:performance_level]).to eq("high")
    end
  end

  describe "#time_to_restore_service" do
    let(:incident_restore_times) do
      [
        double("Metric", timestamp: start_time + 1.day, value: 2.0),   # 2 hours
        double("Metric", timestamp: start_time + 2.days, value: 4.0),  # 4 hours
        double("Metric", timestamp: end_time - 1.day, value: 6.0)      # 6 hours
      ]
    end

    it "calculates time to restore service for a team/project" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.ci.deploy.incident.resolution_time", {}, start_time)
        .and_return(incident_restore_times)

      # Act
      result = repository.time_to_restore_service(start_time: start_time, end_time: end_time)

      # Assert
      expect(result).to be_a(Hash)
      expect(result[:incident_count]).to eq(3)
      expect(result[:average_restore_time_hours]).to eq(4.0)
      expect(result[:median_restore_time_hours]).to eq(4.0)
      expect(result[:p90_restore_time_hours]).to eq(6.0)
      expect(result[:performance_level]).to be_a(String)
    end

    it "applies team filter if provided" do
      # Arrange
      expect(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.ci.deploy.incident.resolution_time", { team_id: team_id }, start_time)
        .and_return(incident_restore_times)

      # Act
      repository.time_to_restore_service(start_time: start_time, end_time: end_time, team_id: team_id)

      # Assert - verification is in the expect().to receive() call above
    end

    it "applies service filter if provided" do
      # Arrange
      expect(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.ci.deploy.incident.resolution_time", { service: service_name }, start_time)
        .and_return(incident_restore_times)

      # Act
      repository.time_to_restore_service(start_time: start_time, end_time: end_time, service: service_name)

      # Assert - verification is in the expect().to receive() call above
    end

    it "applies time range filters" do
      # Arrange - create metrics where one is after the end_time
      metrics = [
        double("Metric", timestamp: start_time + 1.day, value: 4.0),  # Inside range
        double("Metric", timestamp: end_time + 1.day, value: 6.0)     # Outside range (after end_time)
      ]

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.ci.deploy.incident.resolution_time", {}, start_time)
        .and_return(metrics)

      # Act
      result = repository.time_to_restore_service(start_time: start_time, end_time: end_time)

      # Assert
      expect(result[:incident_count]).to eq(1) # Only one metric is within the time range
    end

    it "includes performance label in results" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.ci.deploy.incident.resolution_time", {}, start_time)
        .and_return(incident_restore_times)

      # We'll test each performance level
      allow(repository).to receive(:mttr_label).and_return("medium")

      # Act
      result = repository.time_to_restore_service(start_time: start_time, end_time: end_time)

      # Assert
      expect(result[:performance_level]).to eq("medium")
    end
  end

  describe "#change_failure_rate" do
    let(:github_total_deployments) do
      [double("Metric", timestamp: start_time + 1.day, value: 10.0)]
    end

    let(:github_failed_deployments) do
      [double("Metric", timestamp: start_time + 1.day, value: 2.0)]
    end

    it "calculates change failure rate for a team/project" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.deployment.total", {}, start_time)
        .and_return(github_total_deployments)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.deployment.failure", {}, start_time)
        .and_return(github_failed_deployments)

      # Act
      result = repository.change_failure_rate(start_time: start_time, end_time: end_time)

      # Assert
      expect(result).to be_a(Hash)
      expect(result[:total_deployments]).to eq(10)
      expect(result[:failed_deployments]).to eq(2)
      expect(result[:failure_rate_percentage]).to eq(20.0) # 2/10 * 100 = 20%
      expect(result[:performance_level]).to be_a(String)
    end

    it "applies team filter if provided" do
      # Arrange
      expect(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.deployment.total", { team_id: team_id }, start_time)
        .and_return(github_total_deployments)

      expect(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.deployment.failure", { team_id: team_id }, start_time)
        .and_return(github_failed_deployments)

      # Act
      repository.change_failure_rate(start_time: start_time, end_time: end_time, team_id: team_id)

      # Assert - verification is in the expect().to receive() calls above
    end

    it "applies repository filter if provided" do
      # Arrange
      expect(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.deployment.total", { repository: repository_name }, start_time)
        .and_return(github_total_deployments)

      expect(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.deployment.failure", { repository: repository_name }, start_time)
        .and_return(github_failed_deployments)

      # Act
      repository.change_failure_rate(start_time: start_time, end_time: end_time, repository: repository_name)

      # Assert - verification is in the expect().to receive() calls above
    end

    it "includes performance label in results" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.deployment.total", {}, start_time)
        .and_return(github_total_deployments)

      allow(repository).to receive(:find_metrics_by_name_and_dimensions)
        .with("github.deployment.failure", {}, start_time)
        .and_return(github_failed_deployments)

      # We'll test each performance level
      allow(repository).to receive(:failure_rate_label).and_return("high")

      # Act
      result = repository.change_failure_rate(start_time: start_time, end_time: end_time)

      # Assert
      expect(result[:performance_level]).to eq("high")
    end
  end

  describe "#overall_performance" do
    let(:df_result) { { frequency_per_week: 3.5, performance_level: "high" } }
    let(:lt_result) { { median_lead_time_hours: 36.0, performance_level: "elite" } }
    let(:mttr_result) { { median_restore_time_hours: 4.0, performance_level: "high" } }
    let(:cfr_result) { { failure_rate_percentage: 20.0, performance_level: "high" } }

    it "combines all four DORA metrics" do
      # Arrange
      allow(repository).to receive(:deployment_frequency).and_return(df_result)
      allow(repository).to receive(:lead_time_for_changes).and_return(lt_result)
      allow(repository).to receive(:time_to_restore_service).and_return(mttr_result)
      allow(repository).to receive(:change_failure_rate).and_return(cfr_result)

      # Act
      result = repository.overall_performance(start_time: start_time, end_time: end_time)

      # Assert
      expect(result).to be_a(Hash)
      expect(result[:deployment_frequency]).to eq(df_result)
      expect(result[:lead_time]).to eq(lt_result)
      expect(result[:time_to_restore]).to eq(mttr_result)
      expect(result[:change_failure_rate]).to eq(cfr_result)
      expect(result[:average_score]).to be_a(Float)
      expect(result[:overall_performance_level]).to be_a(String)
    end

    it "passes filters to each individual metric method" do
      # Arrange
      expect(repository).to receive(:deployment_frequency)
        .with(start_time: start_time, end_time: end_time, team_id: team_id, repository: repository_name)
        .and_return(df_result)

      expect(repository).to receive(:lead_time_for_changes)
        .with(start_time: start_time, end_time: end_time, team_id: team_id, repository: repository_name)
        .and_return(lt_result)

      expect(repository).to receive(:time_to_restore_service)
        .with(start_time: start_time, end_time: end_time, team_id: team_id, service: repository_name)
        .and_return(mttr_result)

      expect(repository).to receive(:change_failure_rate)
        .with(start_time: start_time, end_time: end_time, team_id: team_id, repository: repository_name)
        .and_return(cfr_result)

      # Act
      repository.overall_performance(
        start_time: start_time,
        end_time: end_time,
        team_id: team_id,
        repository: repository_name
      )

      # Assert - verification is in the expect().to receive() calls above
    end

    it "calculates an average score from all four metrics" do
      # Arrange - set up different performance levels to test score calculation
      allow(repository).to receive(:deployment_frequency).and_return({ performance_level: "elite" })
      allow(repository).to receive(:lead_time_for_changes).and_return({ performance_level: "high" })
      allow(repository).to receive(:time_to_restore_service).and_return({ performance_level: "medium" })
      allow(repository).to receive(:change_failure_rate).and_return({ performance_level: "low" })

      # Act
      result = repository.overall_performance(start_time: start_time, end_time: end_time)

      # Assert
      # elite(4) + high(3) + medium(2) + low(1) = 10 / 4 = 2.5
      expect(result[:average_score]).to eq(2.5)
    end
  end

  describe "#trend_data" do
    it "generates trend data points for deployment frequency" do
      # Arrange
      expect(repository).to receive(:deployment_frequency).at_least(:once).and_return({
                                                                                        frequency_per_week: 3.5,
                                                                                        performance_level: "high"
                                                                                      })

      # Act
      result = repository.trend_data(
        metric: "deployment_frequency",
        start_time: start_time,
        end_time: end_time
      )

      # Assert
      expect(result).to be_an(Array)
      result.each do |data_point|
        expect(data_point).to include(:start_time, :end_time, :value, :performance_level)
        expect(data_point[:value]).to eq(3.5) # frequency_per_week
      end
    end

    it "generates trend data points for lead time" do
      # Arrange
      expect(repository).to receive(:lead_time_for_changes).at_least(:once).and_return({
                                                                                         median_lead_time_hours: 24.0,
                                                                                         performance_level: "high"
                                                                                       })

      # Act
      result = repository.trend_data(
        metric: "lead_time",
        start_time: start_time,
        end_time: end_time
      )

      # Assert
      expect(result).to be_an(Array)
      result.each do |data_point|
        expect(data_point).to include(:start_time, :end_time, :value, :performance_level)
        expect(data_point[:value]).to eq(24.0) # median_lead_time_hours
      end
    end

    it "applies provided filters to the underlying metrics" do
      # Arrange
      expect(repository).to receive(:deployment_frequency)
        .with(hash_including(team_id: team_id, repository: repository_name))
        .at_least(:once)
        .and_return({ frequency_per_week: 3.5, performance_level: "high" })

      # Act
      repository.trend_data(
        metric: "deployment_frequency",
        start_time: start_time,
        end_time: end_time,
        team_id: team_id,
        repository: repository_name
      )

      # Assert - verification is in the expect().to receive() call above
    end

    it "uses the specified time interval for data points" do
      # Arrange - we'll check that the intervals are right by examining the data points
      allow(repository).to receive(:deployment_frequency).and_return({
                                                                       frequency_per_week: 3.5,
                                                                       performance_level: "high"
                                                                     })

      # Act - use a daily interval
      result = repository.trend_data(
        metric: "deployment_frequency",
        start_time: start_time,
        end_time: end_time,
        interval: "day"
      )

      # Assert - check interval sizes
      expect(result.size).to be > 0
      if result.size > 1
        # Check the difference between consecutive data points is approximately 1 day
        first_point = result[0]
        second_point = result[1]
        interval_seconds = second_point[:start_time] - first_point[:start_time]
        expect(interval_seconds).to be_within(10).of(86_400) # 1 day in seconds
      end
    end
  end

  describe "threshold label calculations" do
    describe "#deployment_frequency_label" do
      it "returns 'elite' for frequencies above the elite threshold" do
        expect(repository.send(:deployment_frequency_label, 8.0)).to eq("elite")
      end

      it "returns 'high' for frequencies above the high threshold" do
        expect(repository.send(:deployment_frequency_label, 3.0)).to eq("high")
      end

      it "returns 'medium' for frequencies above the medium threshold" do
        expect(repository.send(:deployment_frequency_label, 0.3)).to eq("medium")
      end

      it "returns 'low' for frequencies below all thresholds" do
        expect(repository.send(:deployment_frequency_label, 0.1)).to eq("low")
      end
    end

    describe "#lead_time_label" do
      it "returns 'elite' for lead times below the elite threshold" do
        expect(repository.send(:lead_time_label, 12.0)).to eq("elite")
      end

      it "returns 'high' for lead times below the high threshold" do
        expect(repository.send(:lead_time_label, 100.0)).to eq("high")
      end

      it "returns 'medium' for lead times below the medium threshold" do
        expect(repository.send(:lead_time_label, 500.0)).to eq("medium")
      end

      it "returns 'low' for lead times above all thresholds" do
        expect(repository.send(:lead_time_label, 1000.0)).to eq("low")
      end
    end
  end
end
