# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::CodeRepository do
  describe "initialization" do
    context "with valid attributes" do
      it "creates a new code repository with provided attributes" do
        repo = described_class.new(name: "rails-app")

        expect(repo.name).to eq("rails-app")
        expect(repo.id).to be_nil
        expect(repo.url).to be_nil
        expect(repo.provider).to eq("github")
        expect(repo.team_id).to be_nil
        expect(repo.created_at).to be_a(Time)
        expect(repo.updated_at).to be_a(Time)
      end

      it "creates a new code repository with all attributes provided" do
        id = SecureRandom.uuid
        team_id = SecureRandom.uuid
        created_at = 1.day.ago
        updated_at = 1.hour.ago

        repo = described_class.new(
          id: id,
          name: "rails-app",
          url: "https://github.com/org/rails-app",
          provider: "gitlab",
          team_id: team_id,
          created_at: created_at,
          updated_at: updated_at
        )

        expect(repo.id).to eq(id)
        expect(repo.name).to eq("rails-app")
        expect(repo.url).to eq("https://github.com/org/rails-app")
        expect(repo.provider).to eq("gitlab")
        expect(repo.team_id).to eq(team_id)
        expect(repo.created_at).to eq(created_at)
        expect(repo.updated_at).to eq(updated_at)
      end

      it "uses 'github' as the default provider" do
        repo = described_class.new(name: "rails-app")
        expect(repo.provider).to eq("github")
      end
    end

    context "with invalid attributes" do
      it "raises ArgumentError when name is nil" do
        expect { described_class.new(name: nil) }.to raise_error(ArgumentError, "Name cannot be empty")
      end

      it "raises ArgumentError when name is empty" do
        expect { described_class.new(name: "") }.to raise_error(ArgumentError, "Name cannot be empty")
      end

      it "raises ArgumentError when provider is empty" do
        expect do
          described_class.new(name: "rails-app", provider: "")
        end.to raise_error(ArgumentError, "Provider cannot be empty")
      end

      it "raises ArgumentError when provider is nil" do
        expect do
          described_class.new(name: "rails-app", provider: nil)
        end.to raise_error(ArgumentError, "Provider cannot be empty")
      end
    end
  end

  describe "#valid?" do
    it "returns true when name and provider are present" do
      repo = described_class.new(name: "rails-app")
      expect(repo.valid?).to be true
    end
  end

  describe "equality" do
    it "considers repositories with the same attributes equal" do
      repo1 = described_class.new(
        id: "123",
        name: "rails-app",
        url: "https://github.com/org/rails-app",
        provider: "github",
        team_id: "456"
      )

      repo2 = described_class.new(
        id: "123",
        name: "rails-app",
        url: "https://github.com/org/rails-app",
        provider: "github",
        team_id: "456"
      )

      expect(repo1).to eq(repo2)
      expect(repo1.hash).to eq(repo2.hash)
      expect(repo1.eql?(repo2)).to be true
    end

    it "considers repositories with different attributes not equal" do
      repo1 = described_class.new(
        id: "123",
        name: "rails-app",
        url: "https://github.com/org/rails-app",
        provider: "github",
        team_id: "456"
      )

      repo2 = described_class.new(
        id: "789",
        name: "rails-app",
        url: "https://github.com/org/rails-app",
        provider: "github",
        team_id: "456"
      )

      expect(repo1).not_to eq(repo2)
      expect(repo1.hash).not_to eq(repo2.hash)
      expect(repo1.eql?(repo2)).to be false
    end

    it "considers objects of different types not equal" do
      repo = described_class.new(name: "rails-app")
      other_object = Object.new

      expect(repo).not_to eq(other_object)
    end
  end

  describe "#to_h" do
    it "returns a hash representation of the repository" do
      id = "123"
      team_id = "456"
      created_at = Time.new(2023, 1, 1)
      updated_at = Time.new(2023, 1, 2)

      repo = described_class.new(
        id: id,
        name: "rails-app",
        url: "https://github.com/org/rails-app",
        provider: "github",
        team_id: team_id,
        created_at: created_at,
        updated_at: updated_at
      )

      expected_hash = {
        id: id,
        name: "rails-app",
        url: "https://github.com/org/rails-app",
        provider: "github",
        team_id: team_id,
        created_at: created_at,
        updated_at: updated_at
      }

      expect(repo.to_h).to eq(expected_hash)
    end
  end

  describe "#with_id" do
    it "returns a new repository with the updated ID" do
      repo = described_class.new(name: "rails-app")
      new_repo = repo.with_id("new-id")

      expect(new_repo.id).to eq("new-id")
      expect(new_repo.name).to eq(repo.name)
      expect(new_repo.url).to eq(repo.url)
      expect(new_repo.provider).to eq(repo.provider)
      expect(new_repo.team_id).to eq(repo.team_id)
      expect(new_repo.created_at).to eq(repo.created_at)
      expect(new_repo.updated_at).to eq(repo.updated_at)
      expect(new_repo).not_to be(repo) # Should be a different object
    end
  end

  describe "#with_team" do
    it "returns a new repository with the specified team ID" do
      repo = described_class.new(name: "rails-app")
      team_id = "team-123"
      new_repo = repo.with_team(team_id)

      expect(new_repo.team_id).to eq(team_id)
      expect(new_repo.name).to eq(repo.name)
      expect(new_repo.url).to eq(repo.url)
      expect(new_repo.provider).to eq(repo.provider)
      expect(new_repo.id).to eq(repo.id)
      expect(new_repo.created_at).to eq(repo.created_at)
      expect(new_repo.updated_at).to eq(repo.updated_at)
      expect(new_repo).not_to be(repo) # Should be a different object
    end
  end

  describe ".parse_full_name" do
    it "parses a repository name with owner/org and repo parts" do
      result = described_class.parse_full_name("org/repo")
      expect(result).to eq({ owner: "org", repo: "repo" })
    end

    it "handles repository names with multiple slashes" do
      result = described_class.parse_full_name("org/repo/sub")
      expect(result).to eq({ owner: "org", repo: "repo/sub" })
    end

    it "returns the full name as repo when there's no owner/org" do
      result = described_class.parse_full_name("repo")
      expect(result).to eq({ owner: nil, repo: "repo" })
    end

    it "handles nil input" do
      result = described_class.parse_full_name(nil)
      expect(result).to eq({ owner: nil, repo: nil })
    end
  end

  describe "#full_name" do
    it "returns the full repository name" do
      repo = described_class.new(name: "org/repo")
      expect(repo.full_name).to eq("org/repo")
    end

    it "returns just the name when there's no owner/org format" do
      repo = described_class.new(name: "repo")
      expect(repo.full_name).to eq("repo")
    end
  end
end
