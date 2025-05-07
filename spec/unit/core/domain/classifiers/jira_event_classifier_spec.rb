# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::Classifiers::JiraEventClassifier do
  let(:dimension_extractor) { Domain::Extractors::DimensionExtractor.new }
  let(:classifier) { described_class.new(dimension_extractor) }

  describe "#classify" do
    context "with an issue_created event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "jira.issue_created",
          source: "jira",
          data: {
            issue: {
              fields: {
                project: { key: "PROJ" },
                issuetype: { name: "Bug" }
              }
            }
          }
        )
      end

      it "returns the expected metrics" do
        result = classifier.classify(event)

        expect(result).to be_a(Hash)
        expect(result[:metrics]).to be_an(Array)
        expect(result[:metrics].size).to eq(3)

        # Check for issue.total metric
        total_metric = result[:metrics].find { |m| m[:name] == "jira.issue.total" }
        expect(total_metric).to be_present
        expect(total_metric[:value]).to eq(1)
        expect(total_metric[:dimensions][:project]).to eq("PROJ")
        expect(total_metric[:dimensions][:action]).to eq("created")

        # Check for issue.created metric
        created_metric = result[:metrics].find { |m| m[:name] == "jira.issue.created" }
        expect(created_metric).to be_present
        expect(created_metric[:value]).to eq(1)

        # Check for issue.by_type metric
        type_metric = result[:metrics].find { |m| m[:name] == "jira.issue.by_type" }
        expect(type_metric).to be_present
        expect(type_metric[:dimensions][:issue_type]).to eq("Bug")
        expect(type_metric[:dimensions][:action]).to eq("created")
      end
    end

    context "with an issue_resolved event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "jira.issue_resolved",
          source: "jira",
          data: {
            issue: {
              fields: {
                project: { key: "PROJ" },
                issuetype: { name: "Story" }
              }
            }
          }
        )
      end

      it "returns the expected metrics" do
        result = classifier.classify(event)

        expect(result[:metrics].size).to eq(3)

        # Check for issue.total metric with resolved action
        total_metric = result[:metrics].find { |m| m[:name] == "jira.issue.total" }
        expect(total_metric).to be_present
        expect(total_metric[:dimensions][:action]).to eq("resolved")

        # Check for issue.resolved metric
        resolved_metric = result[:metrics].find { |m| m[:name] == "jira.issue.resolved" }
        expect(resolved_metric).to be_present

        # Check for issue.by_type metric with Story type
        type_metric = result[:metrics].find { |m| m[:name] == "jira.issue.by_type" }
        expect(type_metric).to be_present
        expect(type_metric[:dimensions][:issue_type]).to eq("Story")
      end
    end

    context "with a sprint_started event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "jira.sprint_started",
          source: "jira",
          data: {
            project: { key: "PROJ" },
            sprint: { id: 123, name: "Sprint 1" }
          }
        )
      end

      it "returns the expected metrics" do
        result = classifier.classify(event)

        expect(result[:metrics].size).to eq(1)
        expect(result[:metrics].first[:name]).to eq("jira.sprint.started")
        expect(result[:metrics].first[:dimensions][:project]).to eq("PROJ")
      end
    end

    context "with a sprint_closed event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "jira.sprint_closed",
          source: "jira",
          data: {
            project: { key: "PROJ" },
            sprint: { id: 123, name: "Sprint 1" }
          }
        )
      end

      it "returns the expected metrics" do
        result = classifier.classify(event)

        expect(result[:metrics].size).to eq(1)
        expect(result[:metrics].first[:name]).to eq("jira.sprint.closed")
        expect(result[:metrics].first[:dimensions][:project]).to eq("PROJ")
      end
    end

    context "with an unknown Jira event" do
      let(:event) do
        FactoryBot.build(
          :event,
          name: "jira.custom_event",
          source: "jira",
          data: {
            project: { key: "PROJ" }
          }
        )
      end

      it "returns a generic metric" do
        result = classifier.classify(event)

        expect(result[:metrics].size).to eq(1)
        expect(result[:metrics].first[:name]).to eq("jira.custom_event.total")
        expect(result[:metrics].first[:dimensions][:project]).to eq("PROJ")
      end
    end

    context "without a dimension extractor" do
      let(:classifier_without_extractor) { described_class.new }
      let(:event) do
        FactoryBot.build(
          :event,
          name: "jira.issue_created",
          source: "jira",
          data: {
            issue: {
              fields: {
                project: { key: "PROJ" },
                issuetype: { name: "Bug" }
              }
            }
          }
        )
      end

      it "still returns metrics with default values" do
        result = classifier_without_extractor.classify(event)

        expect(result[:metrics]).to be_an(Array)
        expect(result[:metrics].size).to eq(3)

        # Check that dimensions are empty or use default values
        total_metric = result[:metrics].find { |m| m[:name] == "jira.issue.total" }
        expect(total_metric[:dimensions].except(:action)).to eq({})

        # Check that issue type uses default value
        type_metric = result[:metrics].find { |m| m[:name] == "jira.issue.by_type" }
        expect(type_metric[:dimensions][:issue_type]).to eq("unknown")
      end
    end
  end
end
