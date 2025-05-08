# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::ProcessEvent do
  include_context "with all mock ports"

  let(:payload) { '{"event":"test"}' }
  let(:event) do
    Domain::EventFactory.create(
      id: "test-event-id",
      name: "github.push.event",
      data: {
        repository: {
          full_name: "owner/repo",
          html_url: "https://github.com/owner/repo"
        }
      },
      source: "github",
      timestamp: Time.current
    )
  end

  let(:repository) do
    Domain::CodeRepository.new(
      id: 1,
      name: "owner/repo",
      url: "https://github.com/owner/repo",
      provider: "github",
      team_id: 1
    )
  end

  let(:team) do
    Domain::Team.new(
      id: 1,
      name: "owner",
      slug: "owner",
      description: "Auto-created from GitHub organization 'owner'"
    )
  end

  let(:use_case) do
    described_class.new(
      ingestion_port: mock_ingestion_port,
      storage_port: mock_storage_port,
      queue_port: mock_queue_port,
      team_repository_port: mock_team_repository_port,
      logger_port: mock_logger_port
    )
  end

  before do
    # Configure the mock ingestion port to return our test event
    allow(mock_ingestion_port).to receive(:receive_event).and_return(event)

    # Configure the mock storage port to return the event when saved
    allow(mock_storage_port).to receive(:save_event).and_return(event)

    # Configure the mock team repository port to handle repository lookup and save
    allow(mock_team_repository_port).to receive(:find_repository_by_name).and_return(nil)
    allow(mock_team_repository_port).to receive(:save_repository).and_return(repository)

    # Configure team handling
    allow(mock_team_repository_port).to receive(:find_team_by_slug).and_return(nil)
    allow(mock_team_repository_port).to receive(:save_team).and_return(team)

    # Allow call to Team.first for default team handling
    allow(Team).to receive(:first).and_return(nil)
  end

  describe "#call" do
    it "calls ingestion port to parse the event" do
      use_case.call(payload, source: "github")
      expect(mock_ingestion_port).to have_received(:receive_event).with(payload, source: "github")
    end

    it "saves the event to the repository" do
      use_case.call(payload, source: "github")
      expect(mock_storage_port).to have_received(:save_event).with(event)
    end

    it "enqueues the event for metric calculation" do
      use_case.call(payload, source: "github")
      expect(mock_queue_port).to have_received(:enqueue_metric_calculation).with(event)
    end

    context "when it's a GitHub repository event" do
      let(:event) do
        Domain::EventFactory.create(
          id: "test-event-id",
          name: "github.repository.created",
          data: {
            repository: {
              full_name: "owner/repo",
              html_url: "https://github.com/owner/repo"
            }
          },
          source: "github",
          timestamp: Time.current
        )
      end

      it "extracts repository information and registers it" do
        use_case.call(payload, source: "github")

        # Should check if repository exists first in process_repository_from_event
        # and then again in RegisterRepository use case
        expect(mock_team_repository_port).to have_received(:find_repository_by_name).with("owner/repo").at_least(:once)

        # Should save the repository
        expect(mock_team_repository_port).to have_received(:save_repository) do |repo|
          expect(repo.name).to eq("owner/repo")
          expect(repo.url).to eq("https://github.com/owner/repo")
          expect(repo.provider).to eq("github")
          expect(repo.team_id).to eq(1) # Default team ID
        end
      end

      it "creates a team based on the organization name" do
        use_case.call(payload, source: "github")

        # Should attempt to find a team by the organization slug first
        expect(mock_team_repository_port).to have_received(:find_team_by_slug).with("owner")

        # Should create a new team if not found
        expect(mock_team_repository_port).to have_received(:save_team) do |team|
          expect(team.name).to eq("owner")
          expect(team.slug).to eq("owner")
          expect(team.description).to include("Auto-created from GitHub organization")
        end
      end
    end

    context "when it's a GitHub push event" do
      let(:event) do
        Domain::EventFactory.create(
          id: "test-event-id",
          name: "github.push.event",
          data: {
            repository: {
              full_name: "owner/repo",
              html_url: "https://github.com/owner/repo"
            }
          },
          source: "github",
          timestamp: Time.current
        )
      end

      it "extracts repository information and registers it" do
        use_case.call(payload, source: "github")

        # Should check if repository exists first in process_repository_from_event
        # and then again in RegisterRepository use case
        expect(mock_team_repository_port).to have_received(:find_repository_by_name).with("owner/repo").at_least(:once)

        # Should save the repository
        expect(mock_team_repository_port).to have_received(:save_repository) do |repo|
          expect(repo.name).to eq("owner/repo")
          expect(repo.url).to eq("https://github.com/owner/repo")
          expect(repo.provider).to eq("github")
          expect(repo.team_id).to eq(1) # Default team ID
        end
      end
    end

    context "when repository already exists" do
      let(:existing_repo) do
        Domain::CodeRepository.new(
          id: 1,
          name: "owner/repo",
          url: "https://github.com/owner/old-url",
          provider: "github",
          team_id: 2
        )
      end

      before do
        allow(mock_team_repository_port).to receive(:find_repository_by_name).and_return(existing_repo)
      end

      it "updates the existing repository" do
        use_case.call(payload, source: "github")

        # Should check if repository exists first in process_repository_from_event
        # and then again in RegisterRepository use case
        expect(mock_team_repository_port).to have_received(:find_repository_by_name).with("owner/repo").at_least(:once)

        # Should save the repository with updated information
        expect(mock_team_repository_port).to have_received(:save_repository) do |repo|
          expect(repo.id).to eq(1)
          expect(repo.name).to eq("owner/repo")
          expect(repo.url).to eq("https://github.com/owner/repo") # New URL
          expect(repo.provider).to eq("github")
          expect(repo.team_id).to eq(2) # Preserve existing team ID
        end
      end

      it "does not try to create a team for existing repositories with a team" do
        use_case.call(payload, source: "github")

        # Should respect the existing team assignment and not create a new team
        expect(mock_team_repository_port).not_to have_received(:find_team_by_slug)
        expect(mock_team_repository_port).not_to have_received(:save_team)
      end
    end

    context "when a team already exists for an organization" do
      let(:existing_team) do
        Domain::Team.new(
          id: 5,
          name: "owner",
          slug: "owner",
          description: "Existing team"
        )
      end

      before do
        allow(mock_team_repository_port).to receive(:find_team_by_slug).with("owner").and_return(existing_team)
      end

      it "uses the existing team when creating a repository" do
        use_case.call(payload, source: "github")

        # Should try to find the team by slug
        expect(mock_team_repository_port).to have_received(:find_team_by_slug).with("owner")

        # Should not create a new team
        expect(mock_team_repository_port).not_to have_received(:save_team)

        # Should use the existing team's ID when creating the repository
        expect(mock_team_repository_port).to have_received(:save_repository) do |repo|
          expect(repo.team_id).to eq(5) # Existing team ID
        end
      end
    end

    context "when the repository name doesn't contain an organization" do
      let(:event) do
        Domain::EventFactory.create(
          id: "test-event-id",
          name: "github.push.event",
          data: {
            repository: {
              full_name: "simple-repo", # No org part
              html_url: "https://github.com/simple-repo"
            }
          },
          source: "github",
          timestamp: Time.current
        )
      end

      it "uses the default team ID" do
        use_case.call(payload, source: "github")

        # Should not try to create a team
        expect(mock_team_repository_port).not_to have_received(:find_team_by_slug)
        expect(mock_team_repository_port).not_to have_received(:save_team)

        # Should use the default team ID (1 in this case)
        expect(mock_team_repository_port).to have_received(:save_repository) do |repo|
          expect(repo.team_id).to eq(1) # Default team ID
        end
      end
    end
  end
end
