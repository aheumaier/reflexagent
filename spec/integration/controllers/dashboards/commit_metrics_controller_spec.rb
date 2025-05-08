# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboards::CommitMetricsController, type: :controller do
  include Rails.application.routes.url_helpers

  # Define mock metrics service
  let(:mock_metrics_service) { instance_double(MetricsService) }

  # Sample data for the tests
  let(:directory_data) do
    {
      "app" => 8.0,
      "app/models" => 4.0,
      "config" => 4.0
    }
  end

  let(:filetype_data) do
    {
      "rb" => 12.0,
      "html" => 5.0,
      "css" => 3.0
    }
  end

  let(:commit_type_data) do
    {
      "feat" => 10.0,
      "fix" => 5.0,
      "chore" => 3.0
    }
  end

  let(:author_data) do
    {
      "user1" => 5.0,
      "user2" => 3.0,
      "user3" => 2.0
    }
  end

  let(:days) { 30 }

  before do
    # Mock the service factory
    allow(ServiceFactory).to receive(:create_metrics_service).and_return(mock_metrics_service)

    # Mock the metrics service calls
    allow(mock_metrics_service).to receive(:top_metrics)
      .with(any_args)
      .and_return({})

    # Set up specific mock responses
    allow(mock_metrics_service).to receive(:top_metrics)
      .with("github.push.total", dimension: "repository", limit: 1, days: days)
      .and_return({ "test-repo" => 25.0 })

    allow(mock_metrics_service).to receive(:top_metrics)
      .with("github.push.directory_changes.daily", dimension: "directory", limit: 10, days: days)
      .and_return(directory_data)

    allow(mock_metrics_service).to receive(:top_metrics)
      .with("github.push.filetype_changes.daily", dimension: "filetype", limit: 10, days: days)
      .and_return(filetype_data)

    allow(mock_metrics_service).to receive(:top_metrics)
      .with("github.push.commit_type", dimension: "type", limit: 10, days: days)
      .and_return(commit_type_data)

    allow(mock_metrics_service).to receive(:top_metrics)
      .with("github.push.by_author", dimension: "author", limit: 10, days: days)
      .and_return(author_data)

    # Mock the repository list
    allow(mock_metrics_service).to receive(:top_metrics)
      .with("github.push.total", dimension: "repository", limit: 50, days: days)
      .and_return({ "repo1" => 15, "repo2" => 10, "repo3" => 5 })

    # Mock aggregate calls
    allow(mock_metrics_service).to receive(:aggregate)
      .with(any_args)
      .and_return(0)
  end

  describe "#index" do
    it "sets time range variables correctly" do
      get :index

      expect(assigns(:days)).to eq(30) # Default is 30 days
      expect(assigns(:since_date)).to be_present
    end

    it "uses provided days parameter" do
      # For provided days, we need to update the mocks
      allow(mock_metrics_service).to receive(:top_metrics)
        .with("github.push.total", dimension: "repository", limit: 1, days: 90)
        .and_return({ "test-repo" => 25.0 })

      allow(mock_metrics_service).to receive(:top_metrics)
        .with("github.push.total", dimension: "repository", limit: 50, days: 90)
        .and_return({ "repo1" => 15, "repo2" => 10, "repo3" => 5 })

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
