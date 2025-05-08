# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::FindOrCreateTeam do
  include_context "with all mock ports"

  let(:use_case) do
    described_class.new(
      team_repository_port: mock_team_repository_port,
      logger_port: mock_logger_port
    )
  end

  let(:team_name) { "Test Organization" }
  let(:team_slug) { "test-organization" }

  describe "#call" do
    context "when the team already exists" do
      let(:existing_team) do
        Domain::Team.new(
          id: 1,
          name: team_name,
          slug: team_slug
        )
      end

      before do
        allow(mock_team_repository_port).to receive(:find_team_by_slug).with(team_slug).and_return(existing_team)
      end

      it "returns the existing team" do
        result = use_case.call(name: team_name)

        expect(result).to eq(existing_team)
        expect(mock_team_repository_port).to have_received(:find_team_by_slug).with(team_slug)
        expect(mock_team_repository_port).not_to have_received(:save_team)
      end
    end

    context "when the team does not exist" do
      let(:new_team) do
        Domain::Team.new(
          id: 1,
          name: team_name,
          slug: team_slug,
          description: "Auto-created from organization name"
        )
      end

      before do
        allow(mock_team_repository_port).to receive(:find_team_by_slug).with(team_slug).and_return(nil)
        allow(mock_team_repository_port).to receive(:save_team).and_return(new_team)
      end

      it "creates a new team" do
        result = use_case.call(name: team_name)

        expect(result).to eq(new_team)
        expect(mock_team_repository_port).to have_received(:find_team_by_slug).with(team_slug)
        expect(mock_team_repository_port).to have_received(:save_team) do |team|
          expect(team.name).to eq(team_name)
          expect(team.slug).to eq(team_slug)
          expect(team.description).to eq("Auto-created from organization name")
        end
      end

      it "creates a team with custom description if provided" do
        description = "Custom team description"
        result = use_case.call(name: team_name, description: description)

        expect(mock_team_repository_port).to have_received(:save_team) do |team|
          expect(team.description).to eq(description)
        end
      end
    end

    context "with empty or invalid name" do
      it "uses 'Unknown' as a fallback for empty name" do
        result = use_case.call(name: "")

        expect(mock_team_repository_port).to have_received(:find_team_by_slug).with("unknown")
      end

      it "normalizes team names by trimming whitespace" do
        result = use_case.call(name: "  Trim Me  ")

        expect(mock_team_repository_port).to have_received(:find_team_by_slug).with("trim-me")
      end
    end
  end
end
