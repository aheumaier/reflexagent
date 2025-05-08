# frozen_string_literal: true

require "rails_helper"

RSpec.describe DashboardsController, type: :controller do
  let(:mock_dashboard_adapter) { instance_double(Dashboard::DashboardAdapter) }

  # Default test data
  let(:default_commit_metrics) do
    {
      repository: "test-repo",
      directory_hotspots: [],
      file_extension_hotspots: [],
      commit_types: [],
      breaking_changes: { total: 0, by_author: [] },
      author_activity: [],
      commit_volume: { total_commits: 10, days_with_commits: 5, days_analyzed: 30, commits_per_day: 0.33,
                       commit_frequency: 0.17, daily_activity: [] },
      code_churn: { additions: 100, deletions: 50, total_churn: 150, churn_ratio: 2.0 }
    }
  end

  let(:default_dora_metrics) do
    {
      deployment_frequency: { value: 0.5, rating: "high", days_with_deployments: 10, total_days: 30,
                              total_deployments: 15 },
      lead_time: { value: 2.5, rating: "elite", sample_size: 15 },
      time_to_restore: { value: 4.0, rating: "high", sample_size: 3 },
      change_failure_rate: { value: 0.05, rating: "elite", failures: 1, deployments: 20 }
    }
  end

  let(:default_cicd_metrics) do
    {
      builds: {
        total: 25,
        success_rate: 95.0,
        avg_duration: 120.5
      },
      deployments: {
        total: 15,
        success_rate: 93.3,
        avg_duration: 300.2
      }
    }
  end

  let(:default_repo_metrics) do
    {
      push_counts: {},
      active_repos: { "repo1" => 15, "repo2" => 10, "repo3" => 5 },
      commit_volume: {},
      pr_metrics: { open: {}, closed: {}, merged: {} }
    }
  end

  let(:default_team_metrics) do
    {
      top_contributors: { "user1" => 20, "user2" => 15, "user3" => 10 },
      team_velocity: 25,
      pr_review_time: 3.5
    }
  end

  let(:test_alerts) do
    [
      { id: 1, name: "Alert 1", severity: "critical", status: "active" },
      { id: 2, name: "Alert 2", severity: "warning", status: "resolved" }
    ]
  end

  before do
    # Mock the dashboard_adapter method to return our mock adapter
    allow(controller).to receive(:dashboard_adapter).and_return(mock_dashboard_adapter)

    # Set up DependencyContainer mock for testing
    allow(DependencyContainer).to receive(:resolve).with(:dashboard_adapter).and_return(mock_dashboard_adapter)
  end

  describe "#engineering" do
    before do
      # Mock the adapter's methods
      allow(mock_dashboard_adapter).to receive(:get_commit_metrics).and_return(default_commit_metrics)
      allow(mock_dashboard_adapter).to receive(:get_dora_metrics).and_return(default_dora_metrics)
      allow(mock_dashboard_adapter).to receive(:get_cicd_metrics).and_return(default_cicd_metrics)
      allow(mock_dashboard_adapter).to receive(:get_repository_metrics).and_return(default_repo_metrics)
      allow(mock_dashboard_adapter).to receive(:get_team_metrics).and_return(default_team_metrics)
      allow(mock_dashboard_adapter).to receive(:get_recent_alerts).and_return(test_alerts)
    end

    it "sets time range variables correctly" do
      get :engineering

      expect(assigns(:days)).to eq(30) # Default is 30 days
      expect(assigns(:since_date)).to be_present
    end

    it "uses provided days parameter when available" do
      get :engineering, params: { days: 90 }

      expect(assigns(:days)).to eq(90)
    end

    it "fetches metrics from the dashboard adapter" do
      get :engineering

      # Verify the adapter methods were called with correct parameters
      expect(mock_dashboard_adapter).to have_received(:get_commit_metrics).with(time_period: 30)
      expect(mock_dashboard_adapter).to have_received(:get_dora_metrics).with(time_period: 30)
      expect(mock_dashboard_adapter).to have_received(:get_cicd_metrics).with(time_period: 30)
      expect(mock_dashboard_adapter).to have_received(:get_repository_metrics).with(time_period: 30)
      expect(mock_dashboard_adapter).to have_received(:get_team_metrics).with(time_period: 30)
      expect(mock_dashboard_adapter).to have_received(:get_recent_alerts).with(time_period: 30, limit: 5)
    end

    it "assigns metrics to instance variables for the view" do
      get :engineering

      expect(assigns(:commit_metrics)).to eq(default_commit_metrics)
      expect(assigns(:dora_metrics)).to eq(default_dora_metrics)
      expect(assigns(:ci_cd_metrics)).to eq(default_cicd_metrics)
      expect(assigns(:repo_metrics)).to eq(default_repo_metrics)
      expect(assigns(:team_metrics)).to eq(default_team_metrics)
      expect(assigns(:recent_alerts)).to eq(test_alerts)
    end

    it "renders the engineering template" do
      get :engineering

      expect(response).to render_template(:engineering)
    end
  end
end
