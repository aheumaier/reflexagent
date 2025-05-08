# frozen_string_literal: true

require "rails_helper"
require_relative "../../support/use_case_test_helpers"

RSpec.describe "ProcessEvent Integration", type: :integration do
  include UseCaseTestHelpers

  # Create the team before running tests
  let!(:team) { create(:team, name: "Default Team", slug: "default-team") }

  # GitHub push event with repository info
  let(:github_push_event) do
    # Override the default team_id in process_event to use our test team
    allow(Team).to receive(:first).and_return(team)

    Domain::EventFactory.create(
      name: "github.push",
      source: "github",
      data: {
        repository: {
          full_name: "owner/test-repo",
          html_url: "https://github.com/owner/test-repo"
        },
        commits: [
          { id: "abc123", message: "Test commit" }
        ],
        ref: "refs/heads/main"
      },
      timestamp: Time.current
    )
  end

  describe "repository extraction from events" do
    it "creates a new repository when processing a GitHub push event" do
      # Make sure we start with no repository
      CodeRepository.where(name: "owner/test-repo").destroy_all

      # Should not have repository beforehand
      expect(CodeRepository.find_by(name: "owner/test-repo")).to be_nil

      # Create a mock web adapter that returns our prepared event
      web_adapter = instance_double("Web::WebAdapter")
      allow(web_adapter).to receive(:receive_event).and_return(github_push_event)

      # Create clean repositories for test
      event_repo = Repositories::EventRepository.new
      allow(event_repo).to receive(:save_event).and_return(github_push_event)

      # Mock the queue adapter to avoid sending real messages
      queue_adapter = instance_double("Queuing::SidekiqQueueAdapter")
      allow(queue_adapter).to receive(:enqueue_metric_calculation)

      # Use the real team repository
      team_repo = Repositories::TeamRepository.new

      # Create the process event use case with our mocks
      process_event_use_case = UseCases::ProcessEvent.new(
        ingestion_port: web_adapter,
        storage_port: event_repo,
        queue_port: queue_adapter,
        team_repository_port: team_repo,
        logger_port: Rails.logger
      )

      # Mock the extract_org_from_repo method to return the name that matches our test team
      allow_any_instance_of(UseCases::ProcessEvent).to receive(:extract_org_from_repo).and_return("Default Team")

      # Process the GitHub push event with any payload - our mock will return the prepared event
      process_event_use_case.call("{}", source: "github")

      # Check that repository was created
      repo = CodeRepository.find_by(name: "owner/test-repo")
      expect(repo).not_to be_nil
      expect(repo.url).to eq("https://github.com/owner/test-repo")
      expect(repo.provider).to eq("github")
      expect(repo.team_id).to eq(team.id)
    end

    it "updates an existing repository with new information" do
      # Create repository with old URL
      existing_repo = CodeRepository.create!(
        name: "owner/test-repo",
        url: "https://github.com/old-owner/test-repo",
        provider: "github",
        team_id: team.id
      )

      # Create a mock web adapter that returns our prepared event
      web_adapter = instance_double("Web::WebAdapter")
      allow(web_adapter).to receive(:receive_event).and_return(github_push_event)

      # Create clean repositories for test
      event_repo = Repositories::EventRepository.new
      allow(event_repo).to receive(:save_event).and_return(github_push_event)

      # Mock the queue adapter to avoid sending real messages
      queue_adapter = instance_double("Queuing::SidekiqQueueAdapter")
      allow(queue_adapter).to receive(:enqueue_metric_calculation)

      # Use the real team repository
      team_repo = Repositories::TeamRepository.new

      # Create the process event use case with our mocks
      process_event_use_case = UseCases::ProcessEvent.new(
        ingestion_port: web_adapter,
        storage_port: event_repo,
        queue_port: queue_adapter,
        team_repository_port: team_repo,
        logger_port: Rails.logger
      )

      # Mock the extract_org_from_repo method to return the name that matches our test team
      allow_any_instance_of(UseCases::ProcessEvent).to receive(:extract_org_from_repo).and_return("Default Team")

      # Process the GitHub push event with any payload - our mock will return the prepared event
      process_event_use_case.call("{}", source: "github")

      # Repository should be updated with new URL
      existing_repo.reload
      expect(existing_repo.url).to eq("https://github.com/owner/test-repo")
    end
  end
end
