# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboards::CommitMetricsController, :problematic, type: :controller do
  include Rails.application.routes.url_helpers

  describe "#fetch_commit_metrics" do
    let(:metrics_service) { instance_double(MetricsService) }
    let(:days) { 30 }

    # Sample data that would be returned by the metrics service
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

    let(:empty_data) { {} }

    before do
      allow(ServiceFactory).to receive(:create_metrics_service).and_return(metrics_service)

      # Mock all the metrics service calls
      allow(metrics_service).to receive(:top_metrics)
        .with(any_args)
        .and_return(empty_data)

      allow(metrics_service).to receive(:top_metrics)
        .with("github.push.total", dimension: "repository", limit: 1, days: days)
        .and_return({ "test-repo" => 25.0 })

      allow(metrics_service).to receive(:top_metrics)
        .with("github.push.directory_changes.daily", dimension: "directory", limit: 10, days: days)
        .and_return(directory_data)

      allow(metrics_service).to receive(:top_metrics)
        .with("github.push.filetype_changes.daily", dimension: "filetype", limit: 10, days: days)
        .and_return(filetype_data)

      allow(metrics_service).to receive(:top_metrics)
        .with("github.push.commit_type", dimension: "type", limit: 10, days: days)
        .and_return(commit_type_data)

      allow(metrics_service).to receive(:top_metrics)
        .with("github.push.by_author", dimension: "author", limit: 10, days: days)
        .and_return(author_data)

      # Stub the aggregate method for commit volume metrics
      allow(metrics_service).to receive(:aggregate)
        .with(any_args)
        .and_return(0)
    end

    it "retrieves and formats directory hotspots correctly" do
      # Call the private method directly
      metrics = controller.send(:fetch_commit_metrics, days)

      # Check directory hotspots
      expect(metrics[:directory_hotspots]).to be_an(Array)
      expect(metrics[:directory_hotspots].size).to eq(3)

      # Check the structure of the directory hotspots
      app_dir = metrics[:directory_hotspots].find { |d| d[:directory] == "app" }
      expect(app_dir).to be_present
      expect(app_dir[:count]).to eq(8.0)

      models_dir = metrics[:directory_hotspots].find { |d| d[:directory] == "app/models" }
      expect(models_dir).to be_present
      expect(models_dir[:count]).to eq(4.0)
    end

    it "retrieves and formats file extension hotspots correctly" do
      # Call the private method directly
      metrics = controller.send(:fetch_commit_metrics, days)

      # Check file extension hotspots
      expect(metrics[:file_extension_hotspots]).to be_an(Array)
      expect(metrics[:file_extension_hotspots].size).to eq(3)

      # Check the structure of the file extension hotspots
      rb_ext = metrics[:file_extension_hotspots].find { |f| f[:extension] == "rb" }
      expect(rb_ext).to be_present
      expect(rb_ext[:count]).to eq(12.0)

      html_ext = metrics[:file_extension_hotspots].find { |f| f[:extension] == "html" }
      expect(html_ext).to be_present
      expect(html_ext[:count]).to eq(5.0)
    end

    it "handles empty directory and filetype metrics correctly" do
      # Override the mock to return empty data for directory and filetype metrics
      allow(metrics_service).to receive(:top_metrics)
        .with("github.push.directory_changes.daily", dimension: "directory", limit: 10, days: days)
        .and_return({})

      allow(metrics_service).to receive(:top_metrics)
        .with("github.push.filetype_changes.daily", dimension: "filetype", limit: 10, days: days)
        .and_return({})

      # Call the private method directly
      metrics = controller.send(:fetch_commit_metrics, days)

      # Check that empty arrays are returned
      expect(metrics[:directory_hotspots]).to eq([])
      expect(metrics[:file_extension_hotspots]).to eq([])
    end
  end
end
