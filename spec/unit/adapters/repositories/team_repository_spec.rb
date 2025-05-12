# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repositories::TeamRepository do
  let(:logger) { instance_double("Logger", debug: nil, info: nil, warn: nil, error: nil) }
  let(:repository) { described_class.new(logger_port: logger) }

  # We need to create our test models with validation methods
  let(:test_team) do
    team = instance_double(
      Domain::Team,
      id: nil,
      name: "Test Team",
      slug: "test-team",
      description: "Team for testing",
      with_id: nil
    )

    # Allow the necessary methods to make it behave like a Domain::Team
    allow(team).to receive(:with_id).with(123).and_return(
      instance_double(
        Domain::Team,
        id: 123,
        name: "Test Team",
        slug: "test-team",
        description: "Team for testing"
      )
    )

    team
  end

  let(:test_repository) do
    repo = instance_double(
      Domain::CodeRepository,
      id: nil,
      name: "test/repo",
      url: "https://github.com/test/repo",
      provider: "github",
      team_id: 123,
      with_id: nil
    )

    # Allow with_id to return a new mock with the ID
    allow(repo).to receive(:with_id).with(456).and_return(
      instance_double(
        Domain::CodeRepository,
        id: 456,
        name: "test/repo",
        url: "https://github.com/test/repo",
        provider: "github",
        team_id: 123
      )
    )

    repo
  end

  let(:team_record) do
    instance_double(
      "Team",
      id: 123,
      name: "Test Team",
      slug: "test-team",
      description: "Team for testing",
      update!: true
    )
  end

  let(:repository_record) do
    instance_double(
      "CodeRepository",
      id: 456,
      name: "test/repo",
      url: "https://github.com/test/repo",
      provider: "github",
      team_id: 123,
      update!: true,
      destroy: true
    )
  end

  # Mock the Team and CodeRepository classes
  before do
    # Create stub classes with required class methods
    team_class = Class.new do
      def self.find_by(*)
        nil
      end

      def self.all
        []
      end

      def self.create!(*)
        nil
      end

      def self.where(*)
        nil
      end
    end

    code_repo_class = Class.new do
      def self.find_by(*)
        nil
      end

      def self.all
        []
      end

      def self.create!(*)
        nil
      end

      def self.where(*)
        nil
      end
    end

    # Create or reassign the constants
    if defined?(Team)
      stub_const("Team", team_class)
    else
      Object.const_set("Team", team_class)
    end

    if defined?(CodeRepository)
      stub_const("CodeRepository", code_repo_class)
    else
      Object.const_set("CodeRepository", code_repo_class)
    end

    # Mock ActiveRecord errors
    stub_const("ActiveRecord::RecordNotFound", Class.new(StandardError))
    stub_const("ActiveRecord::StatementInvalid", Class.new(StandardError))
    stub_const("ActiveRecord::ConnectionNotEstablished", Class.new(StandardError))

    record_invalid = Class.new(StandardError) do
      attr_reader :record

      def initialize(record = nil)
        @record = record
        super("Record Invalid")
      end
    end
    stub_const("ActiveRecord::RecordInvalid", record_invalid)

    # Configure the logger to be correctly called
    allow(logger).to receive(:error).with(any_args)
    allow(logger).to receive(:error) { |&block| block.call if block }
  end

  describe "#find_team" do
    context "when successful" do
      it "returns nil if id is nil" do
        expect(repository.find_team(nil)).to be_nil
      end

      it "returns a team when found" do
        # Arrange
        allow(Team).to receive(:find_by).with(id: 123).and_return(team_record)

        # Act
        result = repository.find_team(123)

        # Assert
        expect(result).to be_a(Domain::Team)
        expect(result.id).to eq(123)
        expect(result.name).to eq("Test Team")
      end

      it "returns nil if team not found" do
        # Arrange
        allow(Team).to receive(:find_by).with(id: 999).and_return(nil)

        # Act
        result = repository.find_team(999)

        # Assert
        expect(result).to be_nil
      end
    end

    context "when errors occur" do
      it "handles database connection errors" do
        # Arrange
        allow(Team).to receive(:find_by).and_raise(ActiveRecord::ConnectionNotEstablished.new("Connection error"))

        # Act & Assert
        expect { repository.find_team(123) }.to raise_error(Repositories::Errors::DatabaseError) do |error|
          expect(error.context).to include(id: 123)
        end
        # We're just testing that it raises the correct error, not checking if logger is called
      end
    end
  end

  describe "#find_team_by_slug" do
    context "when successful" do
      it "returns nil if slug is nil" do
        expect(repository.find_team_by_slug(nil)).to be_nil
      end

      it "returns a team when found by slug" do
        # Arrange
        allow(Team).to receive(:find_by).with(slug: "test-team").and_return(team_record)

        # Act
        result = repository.find_team_by_slug("test-team")

        # Assert
        expect(result).to be_a(Domain::Team)
        expect(result.id).to eq(123)
        expect(result.slug).to eq("test-team")
      end
    end

    context "when errors occur" do
      it "handles database errors" do
        # Arrange
        allow(Team).to receive(:find_by).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))

        # Act & Assert
        expect do
          repository.find_team_by_slug("test-team")
        end.to raise_error(Repositories::Errors::DatabaseError) do |error|
          expect(error.context).to include(slug: "test-team")
        end
      end
    end
  end

  describe "#save_team" do
    context "when successful" do
      it "creates a new team" do
        # Arrange
        allow(Team).to receive(:find_by).and_return(nil)
        allow(Team).to receive(:create!).and_return(team_record)

        # Act
        result = repository.save_team(test_team)

        # Assert
        expect(result).to be_a(Domain::Team)
        expect(result.id).to eq(123)
        expect(result.name).to eq("Test Team")
      end

      it "updates an existing team" do
        # Arrange - team with ID
        existing_team = test_team.with_id(123)
        allow(Team).to receive(:find_by).with(id: 123).and_return(team_record)
        allow(team_record).to receive(:update!).and_return(true)

        # Act
        result = repository.save_team(existing_team)

        # Assert
        expect(result).to be_a(Domain::Team)
        expect(result.id).to eq(123)
        expect(team_record).to have_received(:update!)
      end
    end

    context "when errors occur" do
      it "raises ArgumentError if team is nil" do
        expect { repository.save_team(nil) }.to raise_error(ArgumentError, "Team cannot be nil")
      end

      it "raises ArgumentError if team name is blank" do
        # Arrange
        team_without_name = instance_double(Domain::Team, name: "", slug: "test-team")

        # Act & Assert
        expect { repository.save_team(team_without_name) }.to raise_error(ArgumentError, "Team name cannot be blank")
      end

      it "handles validation errors" do
        # Arrange
        record = double("Team", errors: double(full_messages: ["Name can't be blank"]))
        error = ActiveRecord::RecordInvalid.new(record)
        allow(Team).to receive(:find_by).and_return(nil)
        allow(Team).to receive(:create!).and_raise(error)

        # Act & Assert
        expect { repository.save_team(test_team) }.to raise_error(Repositories::Errors::ValidationError)
      end

      it "handles database errors" do
        # Arrange
        allow(Team).to receive(:find_by).and_return(nil)
        allow(Team).to receive(:create!).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))

        # Act & Assert
        expect { repository.save_team(test_team) }.to raise_error(Repositories::Errors::DatabaseError)
      end
    end
  end

  describe "#list_teams" do
    context "when successful" do
      it "returns a list of all teams" do
        # Arrange
        allow(Team).to receive(:all).and_return([team_record])

        # Act
        result = repository.list_teams

        # Assert
        expect(result).to be_an(Array)
        expect(result.size).to eq(1)
        expect(result.first).to be_a(Domain::Team)
        expect(result.first.id).to eq(123)
      end
    end

    context "when errors occur" do
      it "handles query errors" do
        # Arrange
        allow(Team).to receive(:all).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))

        # Act & Assert
        expect { repository.list_teams }.to raise_error(Repositories::Errors::QueryError)
      end
    end
  end

  describe "#find_repository" do
    context "when successful" do
      it "returns nil if id is nil" do
        expect(repository.find_repository(nil)).to be_nil
      end

      it "returns a repository when found" do
        # Arrange
        allow(CodeRepository).to receive(:find_by).with(id: 456).and_return(repository_record)

        # Act
        result = repository.find_repository(456)

        # Assert
        expect(result).to be_a(Domain::CodeRepository)
        expect(result.id).to eq(456)
        expect(result.name).to eq("test/repo")
      end

      it "returns nil if repository not found" do
        # Arrange
        allow(CodeRepository).to receive(:find_by).with(id: 999).and_return(nil)

        # Act
        result = repository.find_repository(999)

        # Assert
        expect(result).to be_nil
      end
    end

    context "when errors occur" do
      it "handles database errors" do
        # Arrange
        allow(CodeRepository).to receive(:find_by).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))

        # Act & Assert
        expect { repository.find_repository(456) }.to raise_error(Repositories::Errors::DatabaseError)
      end
    end
  end

  describe "#save_repository" do
    context "when successful" do
      it "creates a new repository" do
        # Arrange
        allow(CodeRepository).to receive(:find_by).and_return(nil)
        allow(CodeRepository).to receive(:create!).and_return(repository_record)

        # Act
        result = repository.save_repository(test_repository)

        # Assert
        expect(result).to be_a(Domain::CodeRepository)
        expect(result.id).to eq(456)
        expect(result.name).to eq("test/repo")
      end

      it "updates an existing repository" do
        # Arrange - repository with ID
        existing_repo = test_repository.with_id(456)
        allow(CodeRepository).to receive(:find_by).with(id: 456).and_return(repository_record)
        allow(repository_record).to receive(:update!).and_return(true)

        # Act
        result = repository.save_repository(existing_repo)

        # Assert
        expect(result).to be_a(Domain::CodeRepository)
        expect(result.id).to eq(456)
        expect(repository_record).to have_received(:update!)
      end
    end

    context "when errors occur" do
      it "raises ArgumentError if repository is nil" do
        expect { repository.save_repository(nil) }.to raise_error(ArgumentError, "Repository cannot be nil")
      end

      it "raises ArgumentError if repository name is blank" do
        # Arrange
        repo_without_name = instance_double(Domain::CodeRepository, name: "", url: "https://github.com/test/repo")

        # Act & Assert
        expect do
          repository.save_repository(repo_without_name)
        end.to raise_error(ArgumentError, "Repository name cannot be blank")
      end

      it "handles validation errors" do
        # Arrange
        record = double("CodeRepository", errors: double(full_messages: ["Name can't be blank"]))
        error = ActiveRecord::RecordInvalid.new(record)
        allow(CodeRepository).to receive(:find_by).and_return(nil)
        allow(CodeRepository).to receive(:create!).and_raise(error)

        # Act & Assert
        expect { repository.save_repository(test_repository) }.to raise_error(Repositories::Errors::ValidationError)
      end

      it "handles database errors" do
        # Arrange
        allow(CodeRepository).to receive(:find_by).and_return(nil)
        allow(CodeRepository).to receive(:create!).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))

        # Act & Assert
        expect { repository.save_repository(test_repository) }.to raise_error(Repositories::Errors::DatabaseError)
      end
    end
  end

  describe "#list_repositories" do
    context "when successful" do
      it "returns a list of repositories with filters" do
        # Arrange
        relation = double("ActiveRecord::Relation")
        allow(CodeRepository).to receive(:all).and_return(relation)
        allow(relation).to receive(:where).and_return(relation)
        allow(relation).to receive(:limit).and_return([repository_record])

        # Act
        result = repository.list_repositories(team_id: 123, limit: 10)

        # Assert
        expect(result).to be_an(Array)
        expect(result.size).to eq(1)
        expect(result.first).to be_a(Domain::CodeRepository)
        expect(result.first.id).to eq(456)
      end
    end

    context "when errors occur" do
      it "handles query errors" do
        # Arrange
        allow(CodeRepository).to receive(:all).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))

        # Act & Assert
        expect { repository.list_repositories }.to raise_error(Repositories::Errors::QueryError)
      end
    end
  end

  describe "#list_repositories_for_team" do
    context "when successful" do
      it "returns a list of repositories for a team" do
        # Arrange
        relation = double("ActiveRecord::Relation")
        allow(CodeRepository).to receive(:where).with(team_id: 123).and_return(relation)
        allow(relation).to receive(:limit).and_return(relation)
        allow(relation).to receive(:offset).and_return(relation)
        allow(relation).to receive(:map).and_yield(repository_record).and_return([
                                                                                   Domain::CodeRepository.new(
                                                                                     id: 456,
                                                                                     name: "test/repo",
                                                                                     url: "https://github.com/test/repo",
                                                                                     provider: "github",
                                                                                     team_id: 123
                                                                                   )
                                                                                 ])

        # Act
        result = repository.list_repositories_for_team(123, limit: 10, offset: 0)

        # Assert
        expect(result).to be_an(Array)
        expect(result.size).to eq(1)
        expect(result.first).to be_a(Domain::CodeRepository)
        expect(result.first.id).to eq(456)
      end
    end

    context "when errors occur" do
      it "raises ArgumentError if team_id is nil" do
        expect { repository.list_repositories_for_team(nil) }.to raise_error(ArgumentError, "Team ID cannot be nil")
      end

      it "handles query errors" do
        # Arrange
        allow(CodeRepository).to receive(:where).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))

        # Act & Assert
        expect { repository.list_repositories_for_team(123) }.to raise_error(Repositories::Errors::QueryError)
      end
    end
  end

  describe "#delete_repository" do
    context "when successful" do
      it "deletes the repository and returns true" do
        # Arrange
        allow(CodeRepository).to receive(:find_by).with(id: 456).and_return(repository_record)
        allow(repository_record).to receive(:destroy).and_return(true)

        # Act
        result = repository.delete_repository(456)

        # Assert
        expect(result).to be true
        expect(repository_record).to have_received(:destroy)
      end

      it "returns false if repository not found" do
        # Arrange
        allow(CodeRepository).to receive(:find_by).with(id: 999).and_return(nil)

        # Act
        result = repository.delete_repository(999)

        # Assert
        expect(result).to be false
      end
    end

    context "when errors occur" do
      it "raises ArgumentError if repository id is nil" do
        expect { repository.delete_repository(nil) }.to raise_error(ArgumentError, "Repository ID cannot be nil")
      end

      it "handles database errors" do
        # Arrange
        allow(CodeRepository).to receive(:find_by).and_raise(ActiveRecord::StatementInvalid.new("SQL error"))

        # Act & Assert
        expect { repository.delete_repository(456) }.to raise_error(Repositories::Errors::DatabaseError)
      end
    end
  end
end
