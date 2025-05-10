# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::DashboardAdapter, type: :integration do
  let(:storage_port) { Repositories::MetricRepository.new }
  let(:cache_port) { instance_double("CachePort", read: nil, write: true) }
  let(:logger_port) { Rails.logger }
  let(:use_case_factory) { UseCaseFactory }

  let(:adapter) do
    described_class.new(
      storage_port: storage_port,
      cache_port: cache_port,
      logger_port: logger_port,
      use_case_factory: use_case_factory
    )
  end

  # Helper method to create test metrics for stubbing
  def create_metric(name, value, dimensions, timestamp)
    instance_double(
      "Domain::Metric",
      id: SecureRandom.uuid,
      name: name,
      value: value,
      dimensions: dimensions,
      timestamp: timestamp,
      source: dimensions["repository"] || "unknown"
    )
  end

  describe "#get_commit_metrics" do
    let(:commit_metrics) do
      [
        create_metric(
          "github.push.commits",
          5,
          { "repository" => "test/repo", "author" => "user1" },
          1.day.ago
        ),
        create_metric(
          "github.push.commits",
          3,
          { "repository" => "test/repo", "author" => "user2" },
          2.days.ago
        )
      ]
    end

    before do
      allow(storage_port).to receive(:list_metrics)
        .with(hash_including(name: "github.push.commits"))
        .and_return(commit_metrics)
    end

    it "returns commit metrics for a repository" do
      result = adapter.get_commit_metrics(time_period: 30, filters: { repository: "test/repo" })

      expect(result).to be_a(Hash)
      expect(result).to include(:repository, :directory_hotspots, :file_extension_hotspots, :commit_types,
                                :breaking_changes, :author_activity, :commit_volume, :code_churn)
    end
  end

  describe "#get_dora_metrics" do
    let(:deployment_frequency_metrics) do
      [
        create_metric(
          "dora.deployment_frequency",
          2.5,
          { "repository" => "test/repo" },
          1.day.ago
        )
      ]
    end

    let(:lead_time_metrics) do
      [
        create_metric(
          "dora.lead_time",
          120,
          { "repository" => "test/repo" },
          1.day.ago
        )
      ]
    end

    let(:time_to_restore_metrics) do
      [
        create_metric(
          "dora.time_to_restore",
          60,
          { "repository" => "test/repo" },
          1.day.ago
        )
      ]
    end

    let(:change_failure_rate_metrics) do
      [
        create_metric(
          "dora.change_failure_rate",
          15.5,
          { "repository" => "test/repo" },
          1.day.ago
        )
      ]
    end

    before do
      allow(storage_port).to receive(:list_metrics)
        .with(hash_including(name: "dora.deployment_frequency"))
        .and_return(deployment_frequency_metrics)

      allow(storage_port).to receive(:list_metrics)
        .with(hash_including(name: "dora.lead_time"))
        .and_return(lead_time_metrics)

      allow(storage_port).to receive(:list_metrics)
        .with(hash_including(name: "dora.time_to_restore"))
        .and_return(time_to_restore_metrics)

      allow(storage_port).to receive(:list_metrics)
        .with(hash_including(name: "dora.change_failure_rate"))
        .and_return(change_failure_rate_metrics)
    end

    it "returns aggregated DORA metrics" do
      result = adapter.get_dora_metrics(time_period: 30)

      expect(result).to be_a(Hash)
      expect(result).to include(:deployment_frequency, :lead_time, :time_to_restore, :change_failure_rate)
    end
  end

  describe "#get_cicd_metrics" do
    # Stub the calls to the storage_port to avoid relying on the database
    let(:build_completed_metrics) do
      [
        create_metric(
          "github.workflow_run.completed",
          1,
          { "repository" => "test/repo", "workflow_name" => "CI", "job_name" => "test", "conclusion" => "success" },
          1.day.ago
        ),
        create_metric(
          "github.workflow_run.completed",
          1,
          { "repository" => "test/repo", "workflow_name" => "CI", "job_name" => "build", "conclusion" => "failure" },
          2.days.ago
        )
      ]
    end

    let(:build_success_metrics) do
      [
        create_metric(
          "github.workflow_run.conclusion.success",
          1,
          { "repository" => "test/repo", "workflow_name" => "CI", "job_name" => "test" },
          1.day.ago
        )
      ]
    end

    let(:build_failure_metrics) do
      [
        create_metric(
          "github.workflow_run.conclusion.failure",
          1,
          { "repository" => "test/repo", "workflow_name" => "CI", "job_name" => "build" },
          2.days.ago
        )
      ]
    end

    let(:build_duration_metrics) do
      [
        create_metric(
          "github.ci.build.duration",
          120,
          { "repository" => "test/repo", "workflow_name" => "CI", "job_name" => "test" },
          1.day.ago
        ),
        create_metric(
          "github.ci.build.duration",
          180,
          { "repository" => "test/repo", "workflow_name" => "CI", "job_name" => "build" },
          2.days.ago
        )
      ]
    end

    let(:deploy_completed_metrics) do
      [
        create_metric(
          "github.ci.deploy.completed",
          1,
          { "repository" => "test/repo", "workflow_name" => "Deploy", "job_name" => "deploy",
            "environment" => "production" },
          1.day.ago
        )
      ]
    end

    let(:deploy_success_metrics) do
      [
        create_metric(
          "github.deployment_status.success",
          1,
          { "repository" => "test/repo", "workflow_name" => "Deploy", "job_name" => "deploy",
            "environment" => "production" },
          1.day.ago
        )
      ]
    end

    let(:deploy_failure_metrics) do
      [
        create_metric(
          "github.ci.deploy.failed",
          1,
          { "repository" => "test/repo", "workflow_name" => "Deploy", "job_name" => "deploy",
            "environment" => "staging" },
          2.days.ago
        )
      ]
    end

    let(:deploy_duration_metrics) do
      [
        create_metric(
          "github.ci.deploy.duration",
          300,
          { "repository" => "test/repo", "workflow_name" => "Deploy", "job_name" => "deploy",
            "environment" => "production" },
          1.day.ago
        )
      ]
    end

    let(:deploy_frequency_metrics) do
      [
        create_metric(
          "dora.deployment_frequency",
          1.5,
          { "repository" => "test/repo" },
          1.day.ago
        )
      ]
    end

    let(:change_failure_rate_metrics) do
      [
        create_metric(
          "dora.change_failure_rate",
          15.5,
          { "repository" => "test/repo" },
          1.day.ago
        )
      ]
    end

    before do
      # Stub the metric repository responses for builds
      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "github.workflow_run.completed")
      ).and_return(build_completed_metrics)

      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "github.workflow_run.conclusion.success")
      ).and_return(build_success_metrics)

      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "github.workflow_run.conclusion.failure")
      ).and_return(build_failure_metrics)

      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "github.ci.build.duration")
      ).and_return(build_duration_metrics)

      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "github.workflow_run.duration")
      ).and_return([])

      # Stub the metric repository responses for deployments
      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "github.ci.deploy.duration")
      ).and_return(deploy_duration_metrics)

      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "github.deployment.duration")
      ).and_return([])

      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "github.ci.deploy.completed")
      ).and_return(deploy_completed_metrics)

      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "github.deployment_status.success")
      ).and_return(deploy_success_metrics)

      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "github.ci.deploy.failed")
      ).and_return(deploy_failure_metrics)

      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "github.deployment_status.failure")
      ).and_return([])

      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "dora.deployment_frequency")
      ).and_return(deploy_frequency_metrics)

      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "github.deployment.created")
      ).and_return([])

      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "dora.change_failure_rate")
      ).and_return(change_failure_rate_metrics)

      allow(storage_port).to receive(:list_metrics).with(
        hash_including(name: "github.check_run.completed")
      ).and_return([])

      # Mock the list_metrics_with_name_pattern call
      allow(storage_port).to receive(:list_metrics_with_name_pattern).with(
        "%deploy%",
        hash_including(start_time: anything)
      ).and_return([])

      # Stub any ActiveRecord calls - we don't want to hit the database in unit tests
      if defined?(DomainMetric)
        allow(DomainMetric).to receive(:where).and_return(double(where: double(count: 0)))
        allow(DomainMetric).to receive(:where).with(name: "github.workflow_run.completed").and_return(double(count: 2))
        allow(DomainMetric).to receive(:where).with(name: "github.workflow_run.conclusion.success").and_return(double(count: 1))
        allow(DomainMetric).to receive(:where).with(name: "github.workflow_run.conclusion.failure").and_return(double(count: 1))
      end

      # Bypass the call to analyze_deployment_performance_use_case
      allow(adapter).to receive(:get_deployment_performance_metrics)
        .with(time_period: 30, repository: "test/repo")
        .and_return({
                      total: 2,
                      success_rate: 90.0,
                      avg_duration: 300.0,
                      deployment_frequency: 1.5,
                      deploys_by_day: { "2023-01-01" => 2 },
                      success_rate_by_day: { "2023-01-01" => 100.0 },
                      deploys_by_workflow: { "deploy" => 2 },
                      durations_by_environment: { "production" => 300.0 },
                      common_failure_reasons: {}
                    })

      # Mock the team_repository and get_available_repositories
      allow(adapter).to receive(:get_available_repositories)
        .with(time_period: anything, limit: anything)
        .and_return(["test/repo"])

      # Add mock for list_team_repositories_use_case
      team_repo_use_case = instance_double("UseCases::ListTeamRepositories")
      allow(adapter).to receive(:list_team_repositories_use_case).and_return(team_repo_use_case)
      allow(team_repo_use_case).to receive(:call).and_return(["test/repo"])
    end

    it "returns properly structured CICD metrics" do
      result = adapter.get_cicd_metrics(time_period: 30, repository: "test/repo")

      expect(result).to include(:builds, :deployments)

      expect(result[:builds]).to include(
        :total,
        :success_rate,
        :avg_duration,
        :builds_by_day,
        :success_by_day,
        :builds_by_workflow,
        :longest_workflow_durations,
        :flaky_builds
      )

      expect(result[:deployments]).to include(
        :total,
        :success_rate,
        :avg_duration,
        :deployment_frequency,
        :deploys_by_day,
        :success_rate_by_day,
        :deploys_by_workflow,
        :durations_by_environment,
        :common_failure_reasons
      )

      # Verify specific values based on our test data
      expect(result[:builds][:total]).to be > 0
      expect(result[:deployments][:total]).to be > 0
    end
  end

  describe "#get_repository_metrics" do
    let(:commit_volume_metrics) do
      [
        create_metric(
          "github.commit_volume.daily",
          10,
          { "date" => "2023-01-01", "repository" => "repo1" },
          Time.parse("2023-01-01")
        ),
        create_metric(
          "github.commit_volume.daily",
          15,
          { "date" => "2023-01-02", "repository" => "repo1" },
          Time.parse("2023-01-02")
        )
      ]
    end

    let(:repo_metrics) do
      [
        create_metric(
          "github.push.commits",
          5,
          { "repository" => "repo1" },
          1.day.ago
        ),
        create_metric(
          "github.push.commits",
          10,
          { "repository" => "repo2" },
          2.days.ago
        )
      ]
    end

    before do
      allow(storage_port).to receive(:list_metrics)
        .with(hash_including(name: "github.commit_volume.daily"))
        .and_return(commit_volume_metrics)

      allow(storage_port).to receive(:list_metrics)
        .with(hash_including(name: "github.push.commits"))
        .and_return(repo_metrics)

      # For PR metrics
      allow(storage_port).to receive(:list_metrics)
        .with(hash_including(name: "github.pull_request.created"))
        .and_return([])

      allow(storage_port).to receive(:list_metrics)
        .with(hash_including(name: "github.pull_request.closed"))
        .and_return([])

      allow(storage_port).to receive(:list_metrics)
        .with(hash_including(name: "github.pull_request.merged"))
        .and_return([])

      # Mock team_repository and get_available_repositories
      allow(adapter).to receive(:get_available_repositories)
        .with(time_period: anything, limit: anything)
        .and_return(["repo1", "repo2"])
    end

    it "returns comprehensive repository metrics" do
      result = adapter.get_repository_metrics(time_period: 30, limit: 5)

      expect(result).to include(:commit_volume, :active_repos, :push_counts, :pr_metrics)
      expect(result[:commit_volume]).to include("2023-01-01" => 10, "2023-01-02" => 15)
      expect(result[:active_repos]).to include("repo1" => 5, "repo2" => 10)
    end
  end

  describe "#get_available_repositories" do
    let(:repository_metrics) do
      [
        create_metric(
          "github.push.commits",
          5,
          { "repository" => "repo1" },
          1.day.ago
        ),
        create_metric(
          "github.push.commits",
          10,
          { "repository" => "repo2" },
          2.days.ago
        ),
        create_metric(
          "github.push.commits",
          3,
          { "repository" => "repo1" },
          3.days.ago
        )
      ]
    end

    before do
      allow(storage_port).to receive(:list_metrics)
        .with(hash_including(name: "github.push.commits"))
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
    end

    it "returns a unique list of repositories" do
      result = adapter.get_available_repositories(time_period: 30, limit: 10)

      expect(result).to include("repo1", "repo2")
      expect(result.size).to eq(2) # Should have de-duplicated repo1
    end

    context "when filtering and sorting" do
      let(:all_repositories) do
        ["repo1", "repo2", "repo3", "repo4", "repo5"].map do |repo|
          create_metric(
            "github.push.commits",
            rand(1..20),
            { "repository" => repo },
            rand(1..5).days.ago
          )
        end
      end

      before do
        allow(storage_port).to receive(:list_metrics)
          .with(hash_including(name: "github.push.commits"))
          .and_return(all_repositories)

        # Mock the team repository to limit to 3 repositories
        mock_team_repo = instance_double("TeamRepositoryPort")
        allow(adapter).to receive(:team_repository).and_return(mock_team_repo)

        # Create three test repositories for the limit test
        three_repos = ["repo1", "repo2", "repo3"].map do |name|
          instance_double("Domain::Repository", name: name)
        end

        allow(mock_team_repo).to receive(:list_repositories).with(limit: 3).and_return(three_repos)
      end

      it "respects the limit parameter" do
        # Create a fresh mock for this test to avoid interference
        allow(adapter).to receive(:get_available_repositories)
          .with(time_period: 30, limit: 3)
          .and_call_original

        result = adapter.get_available_repositories(time_period: 30, limit: 3)

        expect(result.size).to eq(3)
      end
    end
  end

  describe "#update_dashboard_with_metric" do
    let(:metric) do
      instance_double(
        "Domain::Metric",
        id: "metric-123",
        name: "test.metric.value",
        value: 42,
        dimensions: { "repository" => "test/repo" },
        timestamp: Time.current
      )
    end

    it "logs the update and returns true" do
      expect(logger_port).to receive(:info).with("Dashboard updated with metric: test.metric.value")

      result = adapter.update_dashboard_with_metric(metric)

      expect(result).to be true
    end
  end

  describe "#update_dashboard_with_alert" do
    let(:alert) do
      instance_double(
        "Domain::Alert",
        id: "alert-123",
        name: "Critical CPU Usage",
        severity: :critical,
        status: :active,
        timestamp: Time.current
      )
    end

    it "logs the update and returns true" do
      expect(logger_port).to receive(:info).with("Dashboard updated with alert: Critical CPU Usage")

      result = adapter.update_dashboard_with_alert(alert)

      expect(result).to be true
    end
  end

  describe "integration with use cases" do
    context "when calculating complex metrics" do
      # This test ensures that the adapter can work with real use case implementations
      let(:real_storage_port) { double("StoragePort") }
      let(:real_cache_port) { double("CachePort", read: nil, write: true) }

      let(:real_adapter) do
        described_class.new(
          storage_port: real_storage_port,
          cache_port: real_cache_port,
          logger_port: logger_port,
          use_case_factory: use_case_factory
        )
      end

      before do
        # Stub metrics lookups for the storage port
        allow(real_storage_port).to receive(:list_metrics).and_return([])
        allow(real_storage_port).to receive(:find_metric).and_return(nil)
        allow(real_storage_port).to receive(:list_metrics_with_name_pattern).and_return([])

        # Mock team_repository
        mock_team_repo = instance_double("TeamRepositoryPort")
        allow(real_adapter).to receive(:team_repository).and_return(mock_team_repo)
        allow(mock_team_repo).to receive(:list_repositories).and_return([
                                                                          instance_double("Domain::Repository",
                                                                                          name: "repo1"),
                                                                          instance_double("Domain::Repository",
                                                                                          name: "repo2")
                                                                        ])
      end

      it "can fetch commit metrics without errors" do
        expect do
          real_adapter.get_commit_metrics(time_period: 30, filters: { repository: "test/repo" })
        end.not_to raise_error
      end

      it "can fetch DORA metrics without errors" do
        expect do
          real_adapter.get_dora_metrics(time_period: 30)
        end.not_to raise_error
      end

      it "can fetch repository metrics without errors" do
        expect do
          real_adapter.get_repository_metrics(time_period: 30, limit: 5)
        end.not_to raise_error
      end
    end

    context "when there are no metrics available" do
      before do
        # Return empty arrays for all metric queries
        allow(storage_port).to receive(:list_metrics).and_return([])
        allow(storage_port).to receive(:find_metric).and_return(nil)
        allow(storage_port).to receive(:list_metrics_with_name_pattern).and_return([])

        # Mock team_repository
        mock_team_repo = instance_double("TeamRepositoryPort")
        allow(adapter).to receive(:team_repository).and_return(mock_team_repo)
        allow(mock_team_repo).to receive(:list_repositories).and_return([])
      end

      it "returns sensible defaults for commit metrics" do
        result = adapter.get_commit_metrics(time_period: 30, filters: { repository: "test/repo" })

        expect(result).to be_a(Hash)
        expect(result[:author_activity]).to eq([])
        expect(result[:commit_volume]).to include(:total_commits)
        expect(result[:total_commits]).to eq(0) if result[:total_commits]
      end

      it "returns sensible defaults for repository metrics" do
        result = adapter.get_repository_metrics(time_period: 30, limit: 5)

        expect(result).to be_a(Hash)
        expect(result[:active_repos]).to be_a(Hash)
        expect(result[:active_repos]).to be_empty
      end
    end
  end
end
