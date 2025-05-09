# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::Classifiers::GithubEventClassifier do
  let(:dimension_extractor) { Domain::Extractors::DimensionExtractor.new }
  let(:classifier) { described_class.new(dimension_extractor) }

  describe "#classify_push_event" do
    context "with a conventional commit push event" do
      let(:event) do
        # Load push event data from JSON file
        push_data = JSON.parse(
          File.read("test/data/github/push.json")
        ).with_indifferent_access

        FactoryBot.build(
          :event,
          name: "github.push",
          source: "github",
          data: push_data
        )
      end

      it "returns the expected basic push metrics" do
        result = classifier.classify(event)

        expect(result).to be_a(Hash)
        expect(result[:metrics]).to be_an(Array)

        # Check for basic push metrics
        push_metric = result[:metrics].find { |m| m[:name] == "github.push.total" }
        expect(push_metric).to be_present
        expect(push_metric[:value]).to eq(1)
        expect(push_metric[:dimensions][:repository]).to eq("aheumaier/reflexagent")
        expect(push_metric[:dimensions][:organization]).to eq("aheumaier")

        # Check for commit count metric
        commits_metric = result[:metrics].find { |m| m[:name] == "github.push.commits.total" }
        expect(commits_metric).to be_present
        expect(commits_metric[:value]).to eq(1) # There is 1 commit in the sample
      end

      it "properly identifies conventional commit types" do
        result = classifier.classify(event)

        # Check for commit type metric
        commit_type_metric = result[:metrics].find { |m| m[:name] == "github.push.commit_type" }
        expect(commit_type_metric).to be_present
        expect(commit_type_metric[:dimensions][:type]).to eq("fix")
        expect(commit_type_metric[:dimensions][:scope]).to eq("ci")
        expect(commit_type_metric[:dimensions][:conventional]).to eq("true")
      end

      it "tracks file changes and modified paths" do
        result = classifier.classify(event)

        # Check for file modifications
        files_modified_metric = result[:metrics].find { |m| m[:name] == "github.push.files_modified" }
        expect(files_modified_metric).to be_present
        expect(files_modified_metric[:value]).to eq(3) # 3 files were modified

        # Verify file paths metrics
        expect(result[:metrics].find do |m|
          m[:name] == "github.push.directory_changes" &&
                                    m[:dimensions][:directory] == "app/ports"
        end).to be_present
        expect(result[:metrics].find do |m|
          m[:name] == "github.push.directory_changes" &&
                                    m[:dimensions][:directory] == "spec"
        end).to be_present
      end

      it "captures file extension hotspots" do
        result = classifier.classify(event)

        # Ruby file extension should be tracked
        filetype_metric = result[:metrics].find do |m|
          m[:name] == "github.push.filetype_changes" &&
            m[:dimensions][:filetype] == "rb"
        end
        expect(filetype_metric).to be_present
        expect(filetype_metric[:value]).to be > 0
      end

      it "includes branch information in the metrics" do
        result = classifier.classify(event)

        # Check for branch activity metric
        branch_metric = result[:metrics].find { |m| m[:name] == "github.push.branch_activity" }
        expect(branch_metric).to be_present
        expect(branch_metric[:dimensions][:branch]).to eq("main")
      end
    end
  end
end
