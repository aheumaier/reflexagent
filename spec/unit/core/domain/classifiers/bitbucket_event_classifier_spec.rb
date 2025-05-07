# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::Classifiers::BitbucketEventClassifier do
  let(:dimension_extractor) { Domain::Extractors::DimensionExtractor.new }
  let(:classifier) { described_class.new(dimension_extractor) }

  describe "#classify" do
    context "with a repo:push event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "bitbucket.repo:push",
          source: "bitbucket",
          data: {
            repository: { full_name: "acme/repo" },
            push: {
              changes: [
                { commits: [{ hash: "abc123" }, { hash: "def456" }] },
                { commits: [{ hash: "ghi789" }] }
              ]
            }
          }
        )
      end

      it "returns the expected metrics" do
        result = classifier.classify(event)

        expect(result).to be_a(Hash)
        expect(result[:metrics]).to be_an(Array)
        expect(result[:metrics].size).to eq(2)

        # Check for push.total metric
        total_metric = result[:metrics].find { |m| m[:name] == "bitbucket.push.total" }
        expect(total_metric).to be_present
        expect(total_metric[:value]).to eq(1)
        expect(total_metric[:dimensions][:repository]).to eq("acme/repo")

        # Check for push.commits metric
        commits_metric = result[:metrics].find { |m| m[:name] == "bitbucket.push.commits" }
        expect(commits_metric).to be_present
        expect(commits_metric[:value]).to eq(3) # Total commits across all changes
      end
    end

    context "with a pullrequest:created event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "bitbucket.pullrequest:created",
          source: "bitbucket",
          data: {
            repository: { full_name: "acme/repo" },
            pullrequest: { id: 123, title: "Feature PR" }
          }
        )
      end

      it "returns the expected metrics" do
        result = classifier.classify(event)

        expect(result[:metrics].size).to eq(2)

        # Check for pullrequest.total metric
        total_metric = result[:metrics].find { |m| m[:name] == "bitbucket.pullrequest.total" }
        expect(total_metric).to be_present
        expect(total_metric[:dimensions][:action]).to eq("created")

        # Check for pullrequest.created metric
        created_metric = result[:metrics].find { |m| m[:name] == "bitbucket.pullrequest.created" }
        expect(created_metric).to be_present
      end
    end

    context "with a pullrequest:merged event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "bitbucket.pullrequest:merged",
          source: "bitbucket",
          data: {
            repository: { full_name: "acme/repo" },
            pullrequest: { id: 123, title: "Feature PR" }
          }
        )
      end

      it "returns the expected metrics" do
        result = classifier.classify(event)

        expect(result[:metrics].size).to eq(2)

        # Check for pullrequest.total metric with merged action
        total_metric = result[:metrics].find { |m| m[:name] == "bitbucket.pullrequest.total" }
        expect(total_metric).to be_present
        expect(total_metric[:dimensions][:action]).to eq("merged")

        # Check for pullrequest.merged metric
        merged_metric = result[:metrics].find { |m| m[:name] == "bitbucket.pullrequest.merged" }
        expect(merged_metric).to be_present
      end
    end

    context "with an unknown Bitbucket event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "bitbucket.custom_event",
          source: "bitbucket",
          data: {
            repository: { full_name: "acme/repo" }
          }
        )
      end

      it "returns a generic metric" do
        result = classifier.classify(event)

        expect(result[:metrics].size).to eq(1)
        expect(result[:metrics].first[:name]).to eq("bitbucket.custom_event.total")
        expect(result[:metrics].first[:dimensions][:repository]).to eq("acme/repo")
      end
    end

    context "without a dimension extractor" do
      let(:classifier_without_extractor) { described_class.new }
      let(:event) do
        FactoryBot.build(
          :event,
          name: "bitbucket.repo:push",
          source: "bitbucket",
          data: {
            repository: { full_name: "acme/repo" },
            push: {
              changes: [
                { commits: [{ hash: "abc123" }] }
              ]
            }
          }
        )
      end

      it "still returns metrics with default values" do
        result = classifier_without_extractor.classify(event)

        expect(result[:metrics]).to be_an(Array)
        expect(result[:metrics].size).to eq(2)

        # Check that dimensions are empty or use default values
        total_metric = result[:metrics].find { |m| m[:name] == "bitbucket.push.total" }
        expect(total_metric[:dimensions]).to eq({})

        # Check that commit count uses default value
        commits_metric = result[:metrics].find { |m| m[:name] == "bitbucket.push.commits" }
        expect(commits_metric[:value]).to eq(1)
      end
    end
  end
end
