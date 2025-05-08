# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::Team do
  describe "initialization" do
    context "with valid attributes" do
      it "creates a new team with provided attributes" do
        team = described_class.new(name: "Engineering")

        expect(team.name).to eq("Engineering")
        expect(team.slug).to eq("engineering")
        expect(team.id).to be_nil
        expect(team.description).to be_nil
        expect(team.created_at).to be_a(Time)
        expect(team.updated_at).to be_a(Time)
      end

      it "creates a new team with all attributes provided" do
        id = SecureRandom.uuid
        created_at = 1.day.ago
        updated_at = 1.hour.ago

        team = described_class.new(
          id: id,
          name: "Engineering",
          slug: "eng-team",
          description: "The engineering team",
          created_at: created_at,
          updated_at: updated_at
        )

        expect(team.id).to eq(id)
        expect(team.name).to eq("Engineering")
        expect(team.slug).to eq("eng-team")
        expect(team.description).to eq("The engineering team")
        expect(team.created_at).to eq(created_at)
        expect(team.updated_at).to eq(updated_at)
      end

      it "generates a slug from name if not provided" do
        team = described_class.new(name: "Engineering Team")
        expect(team.slug).to eq("engineering-team")
      end

      it "generates a slug from name if slug is nil" do
        team = described_class.new(name: "Team", slug: nil)
        expect(team.slug).to eq("team")
      end
    end

    context "with invalid attributes" do
      it "raises ArgumentError when name is nil" do
        expect { described_class.new(name: nil) }.to raise_error(ArgumentError, "Name cannot be empty")
      end

      it "raises ArgumentError when name is empty" do
        expect { described_class.new(name: "") }.to raise_error(ArgumentError, "Name cannot be empty")
      end

      it "raises ArgumentError when slug becomes empty" do
        expect { described_class.new(name: "Team", slug: "") }.to raise_error(ArgumentError, "Slug cannot be empty")
      end
    end
  end

  describe "#valid?" do
    it "returns true when name and slug are present" do
      team = described_class.new(name: "Engineering")
      expect(team.valid?).to be true
    end
  end

  describe "equality" do
    it "considers teams with the same attributes equal" do
      team1 = described_class.new(
        id: "123",
        name: "Engineering",
        slug: "eng",
        description: "The engineering team"
      )

      team2 = described_class.new(
        id: "123",
        name: "Engineering",
        slug: "eng",
        description: "The engineering team"
      )

      expect(team1).to eq(team2)
      expect(team1.hash).to eq(team2.hash)
      expect(team1.eql?(team2)).to be true
    end

    it "considers teams with different attributes not equal" do
      team1 = described_class.new(
        id: "123",
        name: "Engineering",
        slug: "eng",
        description: "The engineering team"
      )

      team2 = described_class.new(
        id: "456",
        name: "Engineering",
        slug: "eng",
        description: "The engineering team"
      )

      expect(team1).not_to eq(team2)
      expect(team1.hash).not_to eq(team2.hash)
      expect(team1.eql?(team2)).to be false
    end

    it "considers objects of different types not equal" do
      team = described_class.new(name: "Engineering")
      other_object = Object.new

      expect(team).not_to eq(other_object)
    end
  end

  describe "#to_h" do
    it "returns a hash representation of the team" do
      id = "123"
      created_at = Time.new(2023, 1, 1)
      updated_at = Time.new(2023, 1, 2)

      team = described_class.new(
        id: id,
        name: "Engineering",
        slug: "eng",
        description: "The engineering team",
        created_at: created_at,
        updated_at: updated_at
      )

      expected_hash = {
        id: id,
        name: "Engineering",
        slug: "eng",
        description: "The engineering team",
        created_at: created_at,
        updated_at: updated_at
      }

      expect(team.to_h).to eq(expected_hash)
    end
  end

  describe "#with_id" do
    it "returns a new team with the updated ID" do
      team = described_class.new(name: "Engineering", slug: "eng")
      new_team = team.with_id("new-id")

      expect(new_team.id).to eq("new-id")
      expect(new_team.name).to eq(team.name)
      expect(new_team.slug).to eq(team.slug)
      expect(new_team.description).to eq(team.description)
      expect(new_team.created_at).to eq(team.created_at)
      expect(new_team.updated_at).to eq(team.updated_at)
      expect(new_team).not_to be(team) # Should be a different object
    end
  end
end
