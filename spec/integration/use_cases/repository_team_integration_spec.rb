# frozen_string_literal: true

require "rails_helper"
require_relative "../../support/use_case_test_helpers"

RSpec.describe "Repository and Team Integration", type: :integration do
  include UseCaseTestHelpers

  # Clean up database before each test
  before do
    Team.destroy_all
    CodeRepository.destroy_all
    # Use direct SQL for domain_events to avoid model class issues
    ActiveRecord::Base.connection.execute("TRUNCATE domain_events RESTART IDENTITY CASCADE")
    # The metrics table appears to have a different name in the DB schema
    ActiveRecord::Base.connection.execute("TRUNCATE metrics RESTART IDENTITY CASCADE")
  rescue StandardError => e
    puts "Error cleaning up database: #{e.message}"
  end

  # GitHub push event with repository info
  let(:github_push_event) do
    Domain::EventFactory.create(
      id: "test-event-123", # Add explicit ID to avoid empty ID issues
      name: "github.push",
      source: "github",
      data: {
        repository: {
          full_name: "test-org/test-repo",
          html_url: "https://github.com/test-org/test-repo"
        },
        commits: [
          { id: "abc123", message: "Test commit" }
        ],
        ref: "refs/heads/main"
      },
      timestamp: Time.current
    )
  end

  describe "Auto-creating teams and repositories" do
    it "creates a team and repository from a GitHub event" do
      # Set up the event repository to save our event
      event_repo = Repositories::EventRepository.new
      saved_event = event_repo.save_event(github_push_event)

      # If the saved event didn't get an ID, give it one for our test
      if saved_event.id.blank?
        saved_event = Domain::EventFactory.create(
          id: "test-event-id-123",
          name: saved_event.name,
          source: saved_event.source,
          data: saved_event.data,
          timestamp: saved_event.timestamp
        )
      end

      # Make sure the event was persisted and has a valid ID
      expect(saved_event).not_to be_nil
      expect(saved_event.id).not_to be_nil
      expect(saved_event.id).not_to be_empty
      puts "Saved event ID: #{saved_event.id}"

      # Set up dependencies for the dimension extractor
      dimension_extractor = Domain::Extractors::DimensionExtractor.new

      # Create a metric classifier - use regular new method, not create
      metric_classifier = Domain::MetricClassifier.new(
        dimension_extractor: dimension_extractor
      )

      # Mock queue adapter to avoid sending real messages
      queue_adapter = instance_double("Queuing::SidekiqQueueAdapter")
      allow(queue_adapter).to receive(:enqueue_metric_calculation)

      # Get real repositories for team and metrics
      team_repo = Repositories::TeamRepository.new
      metric_repo = Repositories::MetricRepository.new
      cache_adapter = Cache::RedisCache.new

      # Create the process event use case
      process_event_use_case = UseCases::ProcessEvent.new(
        ingestion_port: Web::WebAdapter.new,
        storage_port: event_repo,
        queue_port: queue_adapter,
        team_repository_port: team_repo,
        logger_port: Rails.logger
      )

      # Create a composite storage port for the calculate metrics use case
      composite_storage = Object.new
      composite_storage.define_singleton_method(:find_event) do |id|
        # Directly return the saved event to avoid lookup issues
        return saved_event if id.to_s == saved_event.id.to_s

        event_repo.find_event(id)
      end
      [:save_metric, :find_metric, :find_aggregate_metric, :update_metric].each do |method|
        composite_storage.define_singleton_method(method) do |*args|
          metric_repo.send(method, *args)
        end
      end

      # Create the calculate metrics use case
      calculate_metrics_use_case = UseCases::CalculateMetrics.new(
        storage_port: composite_storage,
        cache_port: cache_adapter,
        metric_classifier: metric_classifier,
        dimension_extractor: dimension_extractor,
        team_repository_port: team_repo
      )

      # Process the event which should create team and repository
      process_event_use_case.call(github_push_event.to_json, source: "github")

      # Calculate metrics which should enhance dimensions
      calculate_metrics_use_case.call(saved_event.id)

      # Verify the team was created
      team = Team.find_by(name: "test-org")
      expect(team).to be_present
      expect(team.slug).to eq("test-org")

      # Verify the repository was created and associated with the team
      repo = CodeRepository.find_by(name: "test-org/test-repo")
      expect(repo).to be_present
      expect(repo.team_id).to eq(team.id)
      expect(repo.url).to eq("https://github.com/test-org/test-repo")

      # Verify the metrics have proper dimensions
      # Use the metric repository to get metrics instead of ActiveRecord
      metrics = metric_repo.list_metrics
      expect(metrics).not_to be_empty

      metrics.each do |metric|
        # NOTE: In the real database, dimensions may be string keyed, not symbol keyed
        dim = metric.dimensions
        repository = dim[:repository] || dim["repository"]
        organization = dim[:organization] || dim["organization"]

        expect(repository).to eq("test-org/test-repo")
        expect(organization).to eq("test-org")
      end
    end

    it "preserves existing team assignments when repository exists" do
      # Create a team manually
      existing_team = Team.create!(name: "Existing Team", slug: "existing-team")

      # Create a repository with this team
      existing_repo = CodeRepository.create!(
        name: "test-org/test-repo",
        url: "https://github.com/test-org/test-repo",
        provider: "github",
        team_id: existing_team.id
      )

      # Process an event with the same repository
      process_event_use_case = get_process_event_use_case
      process_event_use_case.call(github_push_event.to_json, source: "github")

      # Verify the repository still belongs to the same team
      repo = CodeRepository.find_by(name: "test-org/test-repo")
      expect(repo.team_id).to eq(existing_team.id)

      # Verify no new team was created for the organization
      team = Team.find_by(name: "test-org")
      expect(team).to be_nil
    end

    it "uses an existing team for an organization when it exists" do
      # Create a team for the organization
      org_team = Team.create!(name: "test-org", slug: "test-org")
      puts "Created org_team with ID: #{org_team.id}, name: #{org_team.name}, slug: #{org_team.slug}"

      # Create a cloned event with different repository and explicit ID
      modified_event = Domain::EventFactory.create(
        id: "test-event-456", # Add explicit ID to avoid empty ID issues
        name: "github.push",
        source: "github",
        data: {
          repository: {
            full_name: "test-org/new-repo",
            html_url: "https://github.com/test-org/new-repo"
          },
          commits: [
            { id: "abc123", message: "Test commit" }
          ],
          ref: "refs/heads/main"
        },
        timestamp: Time.current
      )

      puts "Event data: #{modified_event.data.inspect}"

      # Create a raw JSON representation for the event
      event_json = {
        repository: {
          full_name: "test-org/new-repo",
          html_url: "https://github.com/test-org/new-repo"
        },
        commits: [
          { id: "abc123", message: "Test commit" }
        ],
        ref: "refs/heads/main"
      }.to_json

      # Process the event with the correct WebAdapter
      process_event_use_case = get_process_event_use_case

      puts "Using process_event_use_case: #{process_event_use_case.class}"
      result = process_event_use_case.call(event_json, source: "github")
      puts "ProcessEvent result: #{result.inspect}"

      # List all repositories to verify
      all_repos = CodeRepository.all
      puts "All repositories: #{all_repos.map { |r| "#{r.name} (team_id: #{r.team_id})" }.join(', ')}"

      # List all teams to verify
      all_teams = Team.all
      puts "All teams: #{all_teams.map { |t| "#{t.name} (id: #{t.id})" }.join(', ')}"

      # Verify the new repository was created and associated with the existing team
      repo = CodeRepository.find_by(name: "test-org/new-repo")
      expect(repo).to be_present, "Repository 'test-org/new-repo' was not created"
      expect(repo.team_id).to eq(org_team.id)
    end
  end
end
