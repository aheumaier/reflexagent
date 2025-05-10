# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::DashboardAdapter do
  let(:storage_port) { instance_double("StoragePort") }
  let(:cache_port) { instance_double("CachePort") }
  let(:logger_port) { instance_double("LoggerPort", debug: nil, info: nil, warn: nil, error: nil) }
  let(:use_case_factory) { class_double("UseCaseFactory") }

  let(:adapter) do
    described_class.new(
      storage_port: storage_port,
      cache_port: cache_port,
      logger_port: logger_port,
      use_case_factory: use_case_factory
    )
  end

  describe "#get_commit_metrics" do
    let(:fetch_engineering_dashboard_metrics_use_case) do
      instance_double("UseCases::FetchEngineeringDashboardMetrics")
    end

    let(:commit_metrics) { { commits_per_day: { "2023-01-01" => 5 } } }
    let(:metrics_response) { { commit_metrics: commit_metrics } }

    before do
      allow(adapter).to receive(:fetch_engineering_dashboard_metrics_use_case)
        .and_return(fetch_engineering_dashboard_metrics_use_case)

      allow(fetch_engineering_dashboard_metrics_use_case).to receive(:call)
        .with(time_period: 30, filters: { repository: "test/repo" })
        .and_return(metrics_response)
    end

    it "delegates to the fetch_engineering_dashboard_metrics use case" do
      result = adapter.get_commit_metrics(time_period: 30, filters: { repository: "test/repo" })

      expect(result).to eq(commit_metrics)
      expect(fetch_engineering_dashboard_metrics_use_case).to have_received(:call)
        .with(time_period: 30, filters: { repository: "test/repo" })
    end
  end

  describe "#get_dora_metrics" do
    let(:deployment_frequency_use_case) { instance_double("UseCases::CalculateDeploymentFrequency") }
    let(:lead_time_use_case) { instance_double("UseCases::CalculateLeadTime") }
    let(:time_to_restore_use_case) { instance_double("UseCases::CalculateTimeToRestore") }
    let(:change_failure_rate_use_case) { instance_double("UseCases::CalculateChangeFailureRate") }

    let(:deployment_frequency) { { deployments_per_day: 2.5 } }
    let(:lead_time) { { average_lead_time: 120 } }
    let(:time_to_restore) { { average_time_to_restore: 60 } }
    let(:change_failure_rate) { { rate: 15.5 } }

    before do
      allow(adapter).to receive(:calculate_deployment_frequency_use_case).and_return(deployment_frequency_use_case)
      allow(adapter).to receive(:calculate_lead_time_use_case).and_return(lead_time_use_case)
      allow(adapter).to receive(:calculate_time_to_restore_use_case).and_return(time_to_restore_use_case)
      allow(adapter).to receive(:calculate_change_failure_rate_use_case).and_return(change_failure_rate_use_case)

      allow(deployment_frequency_use_case).to receive(:call).with(time_period: 30).and_return(deployment_frequency)
      allow(lead_time_use_case).to receive(:call).with(time_period: 30).and_return(lead_time)
      allow(time_to_restore_use_case).to receive(:call).with(time_period: 30).and_return(time_to_restore)
      allow(change_failure_rate_use_case).to receive(:call).with(time_period: 30).and_return(change_failure_rate)
    end

    it "aggregates metrics from all DORA use cases" do
      result = adapter.get_dora_metrics(time_period: 30)

      expect(result).to eq({
                             deployment_frequency: deployment_frequency,
                             lead_time: lead_time,
                             time_to_restore: time_to_restore,
                             change_failure_rate: change_failure_rate
                           })
    end
  end

  describe "#get_cicd_metrics" do
    let(:build_metrics) do
      {
        total: 100,
        success_rate: 85.5,
        avg_duration: 120.0,
        builds_by_day: { "2023-01-01" => 10 },
        success_by_day: { "2023-01-01" => 8 },
        builds_by_workflow: { "workflow1" => 50, "workflow2" => 50 },
        longest_workflow_durations: { "workflow1" => 300 },
        flaky_builds: [{ workflow_name: "workflow1", job_name: "test", rate: 20.0 }]
      }
    end

    let(:deploy_metrics) do
      {
        total: 50,
        success_rate: 90.0,
        avg_duration: 300.0,
        deployment_frequency: 1.5,
        deploys_by_day: { "2023-01-01" => 5 },
        success_rate_by_day: { "2023-01-01" => 80.0 },
        deploys_by_workflow: { "deploy1" => 30, "deploy2" => 20 },
        durations_by_environment: { "production" => 400, "staging" => 200 },
        common_failure_reasons: { "timeout" => 3, "error" => 2 }
      }
    end

    before do
      allow(adapter).to receive(:get_build_performance_metrics)
        .with(time_period: 30, repository: "test/repo")
        .and_return(build_metrics)

      allow(adapter).to receive(:get_deployment_performance_metrics)
        .with(time_period: 30, repository: "test/repo")
        .and_return(deploy_metrics)
    end

    it "combines build and deployment metrics" do
      result = adapter.get_cicd_metrics(time_period: 30, repository: "test/repo")

      expect(result).to eq({
                             builds: build_metrics,
                             deployments: deploy_metrics
                           })
    end

    it "handles nil values in metrics" do
      allow(adapter).to receive(:get_build_performance_metrics)
        .with(time_period: 30, repository: "test/repo")
        .and_return({})

      result = adapter.get_cicd_metrics(time_period: 30, repository: "test/repo")

      expect(result[:builds][:total]).to eq(0)
      expect(result[:builds][:success_rate]).to eq(0)
      expect(result[:builds][:builds_by_day]).to eq({})
    end
  end

  describe "#get_repository_metrics" do
    let(:commit_volume_metrics) do
      [
        instance_double("Domain::Metric",
                        dimensions: { "date" => "2023-01-01" },
                        value: 10),
        instance_double("Domain::Metric",
                        dimensions: { "date" => "2023-01-02" },
                        value: 15)
      ]
    end

    let(:repo_metrics) do
      [
        instance_double("Domain::Metric",
                        dimensions: { "repository" => "repo1" },
                        value: 5),
        instance_double("Domain::Metric",
                        dimensions: { "repository" => "repo2" },
                        value: 10)
      ]
    end

    before do
      allow(storage_port).to receive(:list_metrics)
        .with(name: "github.commit_volume.daily", start_time: anything)
        .and_return(commit_volume_metrics)

      allow(storage_port).to receive(:list_metrics)
        .with(name: "github.push.commits", start_time: anything)
        .and_return(repo_metrics)

      # Mock team_repository
      allow(adapter).to receive(:get_available_repositories)
        .with(time_period: 30, limit: 5)
        .and_return(["repo1", "repo2"])
    end

    it "returns repository metrics" do
      result = adapter.get_repository_metrics(time_period: 30, limit: 5)

      expect(result).to include(:commit_volume, :active_repos, :push_counts, :pr_metrics)
      expect(result[:commit_volume]).to eq({ "2023-01-01" => 10, "2023-01-02" => 15 })
      expect(result[:active_repos]).to include("repo2" => 10, "repo1" => 5)
    end

    context "when no commit volume metrics are found" do
      let(:commit_metrics) do
        [
          instance_double("Domain::Metric",
                          dimensions: { "repository" => "repo1" },
                          value: 5,
                          timestamp: Time.parse("2023-01-01")),
          instance_double("Domain::Metric",
                          dimensions: { "repository" => "repo1" },
                          value: 7,
                          timestamp: Time.parse("2023-01-01")),
          instance_double("Domain::Metric",
                          dimensions: { "repository" => "repo2" },
                          value: 10,
                          timestamp: Time.parse("2023-01-02"))
        ]
      end

      before do
        allow(storage_port).to receive(:list_metrics)
          .with(name: "github.commit_volume.daily", start_time: anything)
          .and_return([])

        allow(storage_port).to receive(:list_metrics)
          .with(name: "github.push.commits", start_time: anything)
          .and_return(commit_metrics)
      end

      it "calculates commit volume from push metrics" do
        result = adapter.get_repository_metrics(time_period: 30, limit: 5)

        expect(result[:commit_volume]).to eq({ "2023-01-01" => 12, "2023-01-02" => 10 })
      end
    end

    context "when no repositories are found through metrics" do
      let(:repository_names) { ["repo1", "repo2"] }
      let(:commit_volume) { { total_commits: 15 } }

      before do
        allow(storage_port).to receive(:list_metrics)
          .with(name: "github.push.commits", start_time: anything)
          .and_return([])

        allow(adapter).to receive(:get_available_repositories)
          .with(time_period: 30, limit: 5)
          .and_return(repository_names)

        allow(adapter).to receive(:calculate_commit_volume_use_case)
          .and_return(instance_double("UseCases::CalculateCommitVolume", call: commit_volume))
      end

      it "tries to get repositories from the database" do
        result = adapter.get_repository_metrics(time_period: 30, limit: 5)

        expect(result[:active_repos]).to include("repo1" => 15, "repo2" => 15)
      end
    end
  end

  describe "#get_team_metrics" do
    let(:team_metrics) { { team_count: 5, commits_per_team: { "team1" => 10 } } }
    let(:metrics_response) { { team_metrics: team_metrics } }
    let(:fetch_engineering_dashboard_metrics_use_case) do
      instance_double("UseCases::FetchEngineeringDashboardMetrics")
    end

    before do
      allow(adapter).to receive(:fetch_engineering_dashboard_metrics_use_case)
        .and_return(fetch_engineering_dashboard_metrics_use_case)

      allow(fetch_engineering_dashboard_metrics_use_case).to receive(:call)
        .with(time_period: 30)
        .and_return(metrics_response)
    end

    it "delegates to the fetch_engineering_dashboard_metrics use case" do
      result = adapter.get_team_metrics(time_period: 30)

      expect(result).to eq(team_metrics)
    end
  end

  describe "#get_recent_alerts" do
    let(:alerts) { [{ id: 1, name: "Alert 1" }, { id: 2, name: "Alert 2" }] }
    let(:list_active_alerts_use_case) { instance_double("UseCases::ListActiveAlerts") }

    before do
      allow(adapter).to receive(:list_active_alerts_use_case).and_return(list_active_alerts_use_case)

      allow(list_active_alerts_use_case).to receive(:call)
        .with(time_period: 30, limit: 5, severity: "high")
        .and_return(alerts)
    end

    it "delegates to the list_active_alerts use case" do
      result = adapter.get_recent_alerts(time_period: 30, limit: 5, severity: "high")

      expect(result).to eq(alerts)
    end
  end

  describe "#get_available_repositories" do
    let(:repository_metrics) do
      [
        instance_double("Domain::Metric", dimensions: { "repository" => "repo1" }),
        instance_double("Domain::Metric", dimensions: { "repository" => "repo2" }),
        instance_double("Domain::Metric", dimensions: { "repository" => "repo1" })
      ]
    end

    before do
      allow(storage_port).to receive(:list_metrics)
        .with(name: "github.push.commits", start_time: anything)
        .and_return(repository_metrics)

      # Mock the team repository
      mock_team_repo = instance_double("TeamRepositoryPort")
      allow(adapter).to receive(:team_repository).and_return(mock_team_repo)
      allow(mock_team_repo).to receive(:list_repositories).and_return([
                                                                        instance_double("Domain::Repository",
                                                                                        name: "repo1"),
                                                                        instance_double("Domain::Repository",
                                                                                        name: "repo2")
                                                                      ])

      # Important: mock list_repositories with limit parameter
      allow(mock_team_repo).to receive(:list_repositories).with(limit: 1).and_return([
                                                                                       instance_double(
                                                                                         "Domain::Repository", name: "repo1"
                                                                                       )
                                                                                     ])
    end

    it "returns a unique list of repositories" do
      result = adapter.get_available_repositories(time_period: 30, limit: 10)

      expect(result).to contain_exactly("repo1", "repo2")
    end

    it "respects the limit parameter" do
      # Mock a direct method response to ensure limit is respected
      allow(adapter).to receive(:get_available_repositories)
        .with(time_period: 30, limit: 1)
        .and_call_original

      # Here we're mocking the team repository to return only one repo when limit is 1
      result = adapter.get_available_repositories(time_period: 30, limit: 1)

      expect(result.size).to eq(1)
    end

    context "when no repositories are found through metrics" do
      let(:repositories) { ["repo1", "repo2", "repo3"] }
      let(:list_team_repositories_use_case) { instance_double("UseCases::ListTeamRepositories") }

      before do
        allow(storage_port).to receive(:list_metrics)
          .with(name: "github.push.commits", start_time: anything)
          .and_return([])

        # Create a custom test response for team repositories use case
        allow(adapter).to receive(:list_team_repositories_use_case)
          .and_return(list_team_repositories_use_case)

        allow(list_team_repositories_use_case).to receive(:call)
          .with(no_args)
          .and_return(repositories)

        # Return the mocked repositories array when called with time_period and limit params
        allow(adapter).to receive(:get_available_repositories)
          .with(time_period: 30, limit: 10)
          .and_return(repositories)
      end

      it "falls back to the team repositories use case" do
        # Call with a different signature to avoid the direct mock we set up above
        allow(adapter).to receive(:get_available_repositories)
          .with(time_period: 30, limit: 10)
          .and_call_original

        # Mock the specific fallback behavior
        expect(adapter).to receive(:team_repository).and_return(
          instance_double("TeamRepositoryPort", list_repositories: repositories.map { |r|
            instance_double("Domain::Repository", name: r)
          })
        )

        result = adapter.get_available_repositories(time_period: 30, limit: 10)
        expect(result).to eq(repositories)
      end
    end
  end

  describe "#get_repository_commit_analysis" do
    let(:directory_hotspots) { [{ directory: "app", count: 10 }] }
    let(:file_extension_hotspots) { [{ extension: "rb", count: 15 }] }
    let(:commit_types) { [{ type: "feat", count: 8 }] }
    let(:breaking_changes) { { total: 3, by_author: [{ author: "user1", count: 2 }] } }
    let(:author_activity) { [{ author: "user1", commits: 10 }] }
    let(:commit_volume) { { total_commits: 25, commits_per_day: 2.5 } }
    let(:code_churn) { { additions: 100, deletions: 50, churn_ratio: 2.0 } }

    before do
      allow(adapter).to receive(:get_directory_hotspots)
        .with(repository: "test/repo", time_period: 30)
        .and_return(directory_hotspots)

      allow(adapter).to receive(:get_file_extension_hotspots)
        .with(repository: "test/repo", time_period: 30)
        .and_return(file_extension_hotspots)

      allow(adapter).to receive(:get_commit_type_distribution)
        .with(repository: "test/repo", time_period: 30)
        .and_return(commit_types)

      allow(adapter).to receive(:get_breaking_changes)
        .with(repository: "test/repo", time_period: 30)
        .and_return(breaking_changes)

      allow(adapter).to receive(:get_author_activity)
        .with(repository: "test/repo", time_period: 30)
        .and_return(author_activity)

      allow(adapter).to receive(:get_commit_volume)
        .with(repository: "test/repo", time_period: 30)
        .and_return(commit_volume)

      allow(adapter).to receive(:get_code_churn)
        .with(repository: "test/repo", time_period: 30)
        .and_return(code_churn)
    end

    it "aggregates results from various analysis methods" do
      result = adapter.get_repository_commit_analysis(repository: "test/repo", time_period: 30)

      expect(result).to include(
        repository: "test/repo",
        directory_hotspots: directory_hotspots,
        file_extension_hotspots: file_extension_hotspots,
        commit_types: commit_types,
        breaking_changes: breaking_changes,
        author_activity: author_activity,
        commit_volume: commit_volume,
        code_churn: code_churn
      )
    end
  end

  describe "#get_directory_hotspots" do
    let(:identify_directory_hotspots_use_case) { instance_double("UseCases::IdentifyDirectoryHotspots") }
    let(:hotspots) { [{ directory: "app/controllers", count: 15 }] }

    before do
      allow(adapter).to receive(:identify_directory_hotspots_use_case)
        .and_return(identify_directory_hotspots_use_case)

      allow(identify_directory_hotspots_use_case).to receive(:call)
        .with(repository: "test/repo", time_period: 30, limit: 10)
        .and_return(hotspots)
    end

    it "delegates to the identify_directory_hotspots use case" do
      result = adapter.get_directory_hotspots(repository: "test/repo", time_period: 30, limit: 10)

      expect(result).to eq(hotspots)
    end
  end

  describe "#get_file_extension_hotspots" do
    let(:analyze_file_type_distribution_use_case) { instance_double("UseCases::AnalyzeFileTypeDistribution") }
    let(:hotspots) { [{ extension: "rb", count: 25 }] }

    before do
      allow(adapter).to receive(:analyze_file_type_distribution_use_case)
        .and_return(analyze_file_type_distribution_use_case)

      allow(analyze_file_type_distribution_use_case).to receive(:call)
        .with(repository: "test/repo", time_period: 30, limit: 10)
        .and_return(hotspots)
    end

    it "delegates to the identify_file_extension_hotspots use case" do
      result = adapter.get_file_extension_hotspots(repository: "test/repo", time_period: 30, limit: 10)

      expect(result).to eq(hotspots)
    end
  end

  describe "#get_commit_type_distribution" do
    let(:classify_commit_types_use_case) { instance_double("UseCases::ClassifyCommitTypes") }
    let(:commit_types) { [{ type: "feat", count: 12, percentage: 40.0 }] }

    before do
      allow(adapter).to receive(:classify_commit_types_use_case)
        .and_return(classify_commit_types_use_case)

      allow(classify_commit_types_use_case).to receive(:call)
        .with(repository: "test/repo", time_period: 30, limit: 10)
        .and_return(commit_types)
    end

    it "delegates to the analyze_commit_types use case" do
      result = adapter.get_commit_type_distribution(repository: "test/repo", time_period: 30, limit: 10)

      expect(result).to eq(commit_types)
    end
  end

  describe "#get_author_activity" do
    let(:track_author_activity_use_case) { instance_double("UseCases::TrackAuthorActivity") }
    let(:activity) { [{ author: "user1", commits: 15, lines_added: 500 }] }

    before do
      allow(adapter).to receive(:track_author_activity_use_case)
        .and_return(track_author_activity_use_case)

      allow(track_author_activity_use_case).to receive(:call)
        .with(repository: "test/repo", time_period: 30, limit: 10)
        .and_return(activity)
    end

    it "delegates to the track_author_activity use case" do
      result = adapter.get_author_activity(repository: "test/repo", time_period: 30, limit: 10)

      expect(result).to eq(activity)
    end
  end

  describe "#get_breaking_changes" do
    let(:detect_breaking_changes_use_case) { instance_double("UseCases::DetectBreakingChanges") }
    let(:breaking_changes) { { total: 5, by_author: [{ author: "user1", count: 3 }] } }

    before do
      allow(adapter).to receive(:detect_breaking_changes_use_case)
        .and_return(detect_breaking_changes_use_case)

      allow(detect_breaking_changes_use_case).to receive(:call)
        .with(repository: "test/repo", time_period: 30)
        .and_return(breaking_changes)
    end

    it "delegates to the detect_breaking_changes use case" do
      result = adapter.get_breaking_changes(repository: "test/repo", time_period: 30)

      expect(result).to eq(breaking_changes)
    end
  end

  describe "#get_commit_volume" do
    let(:calculate_commit_volume_use_case) { instance_double("UseCases::CalculateCommitVolume") }
    let(:commit_volume) { { total_commits: 35, commits_per_day: 3.5 } }

    before do
      allow(adapter).to receive(:calculate_commit_volume_use_case)
        .and_return(calculate_commit_volume_use_case)

      allow(calculate_commit_volume_use_case).to receive(:call)
        .with(repository: "test/repo", time_period: 30)
        .and_return(commit_volume)
    end

    it "delegates to the calculate_commit_volume use case" do
      result = adapter.get_commit_volume(repository: "test/repo", time_period: 30)

      expect(result).to eq(commit_volume)
    end
  end

  describe "#get_code_churn" do
    let(:calculate_code_churn_use_case) { instance_double("UseCases::CalculateCodeChurn") }
    let(:code_churn) { { additions: 200, deletions: 100, churn_ratio: 2.0 } }

    before do
      allow(adapter).to receive(:calculate_code_churn_use_case)
        .and_return(calculate_code_churn_use_case)

      allow(calculate_code_churn_use_case).to receive(:call)
        .with(repository: "test/repo", time_period: 30)
        .and_return(code_churn)
    end

    it "delegates to the calculate_code_churn use case" do
      result = adapter.get_code_churn(repository: "test/repo", time_period: 30)

      expect(result).to eq(code_churn)
    end
  end

  describe "#update_dashboard_with_metric" do
    let(:metric) { instance_double("Domain::Metric", name: "test.metric") }

    it "logs the update and returns true" do
      expect(logger_port).to receive(:info).with("Dashboard updated with metric: test.metric")

      result = adapter.update_dashboard_with_metric(metric)

      expect(result).to be true
    end
  end

  describe "#update_dashboard_with_alert" do
    let(:alert) { instance_double("Domain::Alert", name: "test_alert") }

    it "logs the update and returns true" do
      expect(logger_port).to receive(:info).with("Dashboard updated with alert: test_alert")

      result = adapter.update_dashboard_with_alert(alert)

      expect(result).to be true
    end
  end

  describe "#get_build_performance_metrics" do
    let(:metric_repository) { instance_double("Repositories::MetricRepository") }
    let(:metric_naming_adapter) { instance_double("Adapters::Metrics::MetricNamingAdapter") }
    let(:analyze_build_performance) { instance_double("UseCases::AnalyzeBuildPerformance") }
    let(:build_metrics) { { total: 100, success_rate: 85.5 } }

    before do
      allow(Repositories::MetricRepository).to receive(:new)
        .with(logger_port: logger_port)
        .and_return(metric_repository)

      allow(Adapters::Metrics::MetricNamingAdapter).to receive(:new)
        .and_return(metric_naming_adapter)

      allow(UseCases::AnalyzeBuildPerformance).to receive(:new)
        .with(
          storage_port: metric_repository,
          cache_port: cache_port,
          metric_naming_port: metric_naming_adapter,
          logger_port: logger_port
        )
        .and_return(analyze_build_performance)

      allow(analyze_build_performance).to receive(:call)
        .with(time_period: 30, repository: "test/repo")
        .and_return(build_metrics)
    end

    it "creates and calls the analyze build performance use case" do
      result = adapter.get_build_performance_metrics(time_period: 30, repository: "test/repo")

      expect(result).to eq(build_metrics)
    end
  end

  describe "#get_deployment_performance_metrics" do
    let(:metric_repository) { instance_double("Repositories::MetricRepository") }
    let(:metric_naming_adapter) { instance_double("Adapters::Metrics::MetricNamingAdapter") }
    let(:analyze_deployment_performance) { instance_double("UseCases::AnalyzeDeploymentPerformance") }
    let(:deploy_metrics) { { total: 50, success_rate: 90.0 } }

    before do
      allow(Repositories::MetricRepository).to receive(:new)
        .with(logger_port: logger_port)
        .and_return(metric_repository)

      allow(Adapters::Metrics::MetricNamingAdapter).to receive(:new)
        .and_return(metric_naming_adapter)

      allow(UseCases::AnalyzeDeploymentPerformance).to receive(:new)
        .with(
          storage_port: metric_repository,
          cache_port: cache_port,
          metric_naming_port: metric_naming_adapter,
          logger_port: logger_port
        )
        .and_return(analyze_deployment_performance)

      allow(analyze_deployment_performance).to receive(:call)
        .with(time_period: 30, repository: "test/repo")
        .and_return(deploy_metrics)
    end

    it "creates and calls the analyze deployment performance use case" do
      result = adapter.get_deployment_performance_metrics(time_period: 30, repository: "test/repo")

      expect(result).to eq(deploy_metrics)
    end
  end
end
