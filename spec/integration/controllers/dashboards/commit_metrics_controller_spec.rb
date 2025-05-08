# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboards::CommitMetricsController, type: :controller do
  include Rails.application.routes.url_helpers

  # Define mock dashboard adapter
  let(:mock_dashboard_adapter) { instance_double(Dashboard::DashboardAdapter) }

  # Sample data for the tests
  let(:directory_hotspots) do
    [
      { directory: "app", count: 8.0 },
      { directory: "app/models", count: 4.0 },
      { directory: "config", count: 4.0 }
    ]
  end

  let(:file_extension_hotspots) do
    [
      { extension: "rb", count: 12.0 },
      { extension: "html", count: 5.0 },
      { extension: "css", count: 3.0 }
    ]
  end

  let(:commit_types) do
    [
      { type: "feat", count: 10.0, percentage: 55.6 },
      { type: "fix", count: 5.0, percentage: 27.8 },
      { type: "chore", count: 3.0, percentage: 16.7 }
    ]
  end

  let(:author_activity) do
    [
      { author: "user1", commit_count: 5.0, lines_added: 0, lines_deleted: 0, lines_changed: 0 },
      { author: "user2", commit_count: 3.0, lines_added: 0, lines_deleted: 0, lines_changed: 0 },
      { author: "user3", commit_count: 2.0, lines_added: 0, lines_deleted: 0, lines_changed: 0 }
    ]
  end

  let(:breaking_changes) do
    { total: 0, by_author: [] }
  end

  let(:commit_volume) do
    {
      total_commits: 10,
      days_with_commits: 5,
      days_analyzed: 30,
      commits_per_day: 0.33,
      commit_frequency: 0.17,
      daily_activity: []
    }
  end

  let(:code_churn) do
    {
      additions: 0,
      deletions: 0,
      total_churn: 0,
      churn_ratio: 0
    }
  end

  let(:repository_commit_analysis) do
    {
      repository: "test-repo",
      directory_hotspots: directory_hotspots,
      file_extension_hotspots: file_extension_hotspots,
      commit_types: commit_types,
      author_activity: author_activity,
      breaking_changes: breaking_changes,
      commit_volume: commit_volume,
      code_churn: code_churn
    }
  end

  let(:specific_repo_analysis) do
    repository_commit_analysis.merge(repository: "specific-repo")
  end

  let(:days) { 30 }
  let(:available_repositories) { ["repo1", "repo2", "repo3"] }

  before do
    # Mock the dashboard_adapter method to return our mock adapter
    allow(controller).to receive(:dashboard_adapter).and_return(mock_dashboard_adapter)

    # Mock the repository list
    allow(mock_dashboard_adapter).to receive(:get_available_repositories)
      .with(time_period: days, limit: 50)
      .and_return(available_repositories)

    # Mock get_available_repositories with limit 1 for top repo
    allow(mock_dashboard_adapter).to receive(:get_available_repositories)
      .with(time_period: days, limit: 1)
      .and_return(["test-repo"])

    # Mock get_repository_commit_analysis for default repository
    allow(mock_dashboard_adapter).to receive(:get_repository_commit_analysis)
      .with(repository: "test-repo", time_period: days)
      .and_return(repository_commit_analysis)

    # Mock get_repository_commit_analysis for specific repository
    allow(mock_dashboard_adapter).to receive(:get_repository_commit_analysis)
      .with(repository: "specific-repo", time_period: days)
      .and_return(specific_repo_analysis)
  end

  describe "#index" do
    it "sets time range variables correctly" do
      get :index

      expect(assigns(:days)).to eq(30) # Default is 30 days
      expect(assigns(:since_date)).to be_present
    end

    it "uses provided days parameter" do
      # For provided days, we need to update the mocks
      allow(mock_dashboard_adapter).to receive(:get_available_repositories)
        .with(time_period: 90, limit: 1)
        .and_return(["test-repo"])

      allow(mock_dashboard_adapter).to receive(:get_available_repositories)
        .with(time_period: 90, limit: 50)
        .and_return(available_repositories)

      allow(mock_dashboard_adapter).to receive(:get_repository_commit_analysis)
        .with(repository: "test-repo", time_period: 90)
        .and_return(repository_commit_analysis)

      get :index, params: { days: 90 }

      expect(assigns(:days)).to eq(90)
    end

    it "uses provided repository parameter when available" do
      get :index, params: { repository: "specific-repo" }

      expect(assigns(:repository)).to eq("specific-repo")
      expect(assigns(:commit_metrics)[:repository]).to eq("specific-repo")
    end

    it "uses the top repository when none provided" do
      get :index

      expect(assigns(:commit_metrics)[:repository]).to eq("test-repo")
    end

    it "formats directory hotspots data correctly" do
      get :index

      # Check directory hotspots
      expect(assigns(:commit_metrics)[:directory_hotspots]).to be_an(Array)
      expect(assigns(:commit_metrics)[:directory_hotspots].size).to eq(3)

      # Check format of the directory hotspots
      app_dir = assigns(:commit_metrics)[:directory_hotspots].find { |d| d[:directory] == "app" }
      expect(app_dir).to be_present
      expect(app_dir[:count]).to eq(8.0)
    end

    it "formats file extension hotspots data correctly" do
      get :index

      # Check file extension hotspots
      expect(assigns(:commit_metrics)[:file_extension_hotspots]).to be_an(Array)
      expect(assigns(:commit_metrics)[:file_extension_hotspots].size).to eq(3)

      # Check format of the file extension hotspots
      rb_ext = assigns(:commit_metrics)[:file_extension_hotspots].find { |f| f[:extension] == "rb" }
      expect(rb_ext).to be_present
      expect(rb_ext[:count]).to eq(12.0)
    end

    it "formats commit types data correctly" do
      get :index

      # Check commit types
      expect(assigns(:commit_metrics)[:commit_types]).to be_an(Array)
      expect(assigns(:commit_metrics)[:commit_types].size).to eq(3)

      # Check a specific type
      feat_type = assigns(:commit_metrics)[:commit_types].find { |t| t[:type] == "feat" }
      expect(feat_type).to be_present
      expect(feat_type[:count]).to eq(10.0)
      expect(feat_type[:percentage]).to be_present # Check percentage is calculated
    end

    it "handles repository list correctly" do
      get :index

      expect(assigns(:repositories)).to be_an(Array)
      expect(assigns(:repositories).size).to eq(3)
      expect(assigns(:repositories)).to include("repo1", "repo2", "repo3")
    end

    it "renders the index template" do
      get :index

      expect(response).to render_template(:index)
    end
  end
end
