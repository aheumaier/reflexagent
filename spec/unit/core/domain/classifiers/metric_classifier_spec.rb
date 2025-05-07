# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::Classifiers::MetricClassifier do
  let(:dimension_extractor) { instance_double("Domain::Extractors::DimensionExtractor") }
  let(:github_classifier) { instance_double("Domain::Classifiers::GithubClassifier") }
  let(:jira_classifier) { instance_double("Domain::Classifiers::JiraClassifier") }
  let(:gitlab_classifier) { instance_double("Domain::Classifiers::GitlabClassifier") }
  let(:bitbucket_classifier) { instance_double("Domain::Classifiers::BitbucketClassifier") }
  let(:ci_classifier) { instance_double("Domain::Classifiers::CiClassifier") }
  let(:task_classifier) { instance_double("Domain::Classifiers::TaskClassifier") }
  let(:generic_classifier) { instance_double("Domain::Classifiers::GenericClassifier") }

  let(:classifiers) do
    {
      github: github_classifier,
      jira: jira_classifier,
      gitlab: gitlab_classifier,
      bitbucket: bitbucket_classifier,
      ci: ci_classifier,
      task: task_classifier,
      generic: generic_classifier
    }
  end

  let(:classifier) { described_class.new(classifiers, dimension_extractor) }

  describe "#initialize" do
    it "initializes with classifiers and dimension extractor" do
      expect(classifier.dimension_extractor).to eq(dimension_extractor)
      expect(classifier.github_classifier).to eq(github_classifier)
      expect(classifier.jira_classifier).to eq(jira_classifier)
      expect(classifier.gitlab_classifier).to eq(gitlab_classifier)
      expect(classifier.bitbucket_classifier).to eq(bitbucket_classifier)
      expect(classifier.ci_classifier).to eq(ci_classifier)
      expect(classifier.task_classifier).to eq(task_classifier)
      expect(classifier.generic_classifier).to eq(generic_classifier)
    end

    it "works with no parameters" do
      classifier = described_class.new

      expect(classifier.dimension_extractor).to be_a(Domain::Extractors::DimensionExtractor)
      expect(classifier.github_classifier).to be_nil
      expect(classifier.jira_classifier).to be_nil
      expect(classifier.gitlab_classifier).to be_nil
      expect(classifier.bitbucket_classifier).to be_nil
      expect(classifier.ci_classifier).to be_nil
      expect(classifier.task_classifier).to be_nil
      expect(classifier.generic_classifier).to be_nil
    end
  end

  describe "#classify_event" do
    context "with GitHub events" do
      let(:github_event) { FactoryBot.build(:event, name: "github.push") }
      let(:expected_result) { { metrics: [{ name: "test.metric", value: 1 }] } }

      it "delegates to github_classifier if available" do
        allow(github_classifier).to receive(:classify).with(github_event).and_return(expected_result)

        result = classifier.classify_event(github_event)

        expect(github_classifier).to have_received(:classify).with(github_event)
        expect(result).to eq(expected_result)
      end

      it "falls back to classify_github_event if classifier not available" do
        classifier = described_class.new({}, dimension_extractor)
        allow(classifier).to receive(:classify_github_event).with(github_event).and_return(expected_result)

        result = classifier.classify_event(github_event)

        expect(classifier).to have_received(:classify_github_event).with(github_event)
        expect(result).to eq(expected_result)
      end
    end

    context "with Jira events" do
      let(:jira_event) { FactoryBot.build(:event, name: "jira.issue.created") }
      let(:expected_result) { { metrics: [{ name: "test.metric", value: 1 }] } }

      it "delegates to jira_classifier if available" do
        allow(jira_classifier).to receive(:classify).with(jira_event).and_return(expected_result)

        result = classifier.classify_event(jira_event)

        expect(jira_classifier).to have_received(:classify).with(jira_event)
        expect(result).to eq(expected_result)
      end

      it "falls back to classify_jira_event if classifier not available" do
        classifier = described_class.new({}, dimension_extractor)
        allow(classifier).to receive(:classify_jira_event).with(jira_event).and_return(expected_result)

        result = classifier.classify_event(jira_event)

        expect(classifier).to have_received(:classify_jira_event).with(jira_event)
        expect(result).to eq(expected_result)
      end
    end

    context "with GitLab events" do
      let(:gitlab_event) { FactoryBot.build(:event, name: "gitlab.push") }
      let(:expected_result) { { metrics: [{ name: "test.metric", value: 1 }] } }

      it "delegates to gitlab_classifier if available" do
        allow(gitlab_classifier).to receive(:classify).with(gitlab_event).and_return(expected_result)

        result = classifier.classify_event(gitlab_event)

        expect(gitlab_classifier).to have_received(:classify).with(gitlab_event)
        expect(result).to eq(expected_result)
      end

      it "falls back to classify_gitlab_event if classifier not available" do
        classifier = described_class.new({}, dimension_extractor)
        allow(classifier).to receive(:classify_gitlab_event).with(gitlab_event).and_return(expected_result)

        result = classifier.classify_event(gitlab_event)

        expect(classifier).to have_received(:classify_gitlab_event).with(gitlab_event)
        expect(result).to eq(expected_result)
      end
    end

    context "with Bitbucket events" do
      let(:bitbucket_event) { FactoryBot.build(:event, name: "bitbucket.push") }
      let(:expected_result) { { metrics: [{ name: "test.metric", value: 1 }] } }

      it "delegates to bitbucket_classifier if available" do
        allow(bitbucket_classifier).to receive(:classify).with(bitbucket_event).and_return(expected_result)

        result = classifier.classify_event(bitbucket_event)

        expect(bitbucket_classifier).to have_received(:classify).with(bitbucket_event)
        expect(result).to eq(expected_result)
      end

      it "falls back to classify_bitbucket_event if classifier not available" do
        classifier = described_class.new({}, dimension_extractor)
        allow(classifier).to receive(:classify_bitbucket_event).with(bitbucket_event).and_return(expected_result)

        result = classifier.classify_event(bitbucket_event)

        expect(classifier).to have_received(:classify_bitbucket_event).with(bitbucket_event)
        expect(result).to eq(expected_result)
      end
    end

    context "with CI events" do
      let(:ci_event) { FactoryBot.build(:event, name: "ci.build.completed") }
      let(:expected_result) { { metrics: [{ name: "test.metric", value: 1 }] } }

      it "delegates to ci_classifier if available" do
        allow(ci_classifier).to receive(:classify).with(ci_event).and_return(expected_result)

        result = classifier.classify_event(ci_event)

        expect(ci_classifier).to have_received(:classify).with(ci_event)
        expect(result).to eq(expected_result)
      end

      it "falls back to classify_ci_event if classifier not available" do
        classifier = described_class.new({}, dimension_extractor)
        allow(classifier).to receive(:classify_ci_event).with(ci_event).and_return(expected_result)

        result = classifier.classify_event(ci_event)

        expect(classifier).to have_received(:classify_ci_event).with(ci_event)
        expect(result).to eq(expected_result)
      end
    end

    context "with Task events" do
      let(:task_event) { FactoryBot.build(:event, name: "task.created") }
      let(:expected_result) { { metrics: [{ name: "test.metric", value: 1 }] } }

      it "delegates to task_classifier if available" do
        allow(task_classifier).to receive(:classify).with(task_event).and_return(expected_result)

        result = classifier.classify_event(task_event)

        expect(task_classifier).to have_received(:classify).with(task_event)
        expect(result).to eq(expected_result)
      end

      it "falls back to classify_task_event if classifier not available" do
        classifier = described_class.new({}, dimension_extractor)
        allow(classifier).to receive(:classify_task_event).with(task_event).and_return(expected_result)

        result = classifier.classify_event(task_event)

        expect(classifier).to have_received(:classify_task_event).with(task_event)
        expect(result).to eq(expected_result)
      end
    end

    context "with unknown events" do
      let(:unknown_event) { FactoryBot.build(:event, name: "unknown.event") }
      let(:expected_result) { { metrics: [{ name: "test.metric", value: 1 }] } }

      it "delegates to generic_classifier if available" do
        allow(generic_classifier).to receive(:classify).with(unknown_event).and_return(expected_result)

        result = classifier.classify_event(unknown_event)

        expect(generic_classifier).to have_received(:classify).with(unknown_event)
        expect(result).to eq(expected_result)
      end

      it "falls back to classify_generic_event if classifier not available" do
        classifier = described_class.new({}, dimension_extractor)
        allow(classifier).to receive(:classify_generic_event).with(unknown_event).and_return(expected_result)

        result = classifier.classify_event(unknown_event)

        expect(classifier).to have_received(:classify_generic_event).with(unknown_event)
        expect(result).to eq(expected_result)
      end
    end
  end
end
