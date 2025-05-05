# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::Extractors::DimensionExtractor do
  let(:extractor) { described_class.new }

  describe "#extract_dimensions" do
    context "with a GitHub event" do
      let(:github_event) { FactoryBot.build(:event, name: "github.push", source: "github") }

      it "delegates to extract_github_dimensions" do
        allow(extractor).to receive(:extract_github_dimensions).and_return({ test: "value" })

        result = extractor.extract_dimensions(github_event)

        expect(extractor).to have_received(:extract_github_dimensions).with(github_event)
        expect(result).to eq({ test: "value" })
      end
    end

    context "with a Jira event" do
      let(:jira_event) { FactoryBot.build(:event, name: "jira.issue.created", source: "jira") }

      it "delegates to extract_jira_dimensions" do
        allow(extractor).to receive(:extract_jira_dimensions).and_return({ test: "value" })

        result = extractor.extract_dimensions(jira_event)

        expect(extractor).to have_received(:extract_jira_dimensions).with(jira_event)
        expect(result).to eq({ test: "value" })
      end
    end

    context "with a GitLab event" do
      let(:gitlab_event) { FactoryBot.build(:event, name: "gitlab.push", source: "gitlab") }

      it "delegates to extract_gitlab_dimensions" do
        allow(extractor).to receive(:extract_gitlab_dimensions).and_return({ test: "value" })

        result = extractor.extract_dimensions(gitlab_event)

        expect(extractor).to have_received(:extract_gitlab_dimensions).with(gitlab_event)
        expect(result).to eq({ test: "value" })
      end
    end

    context "with a Bitbucket event" do
      let(:bitbucket_event) { FactoryBot.build(:event, name: "bitbucket.push", source: "bitbucket") }

      it "delegates to extract_bitbucket_dimensions" do
        allow(extractor).to receive(:extract_bitbucket_dimensions).and_return({ test: "value" })

        result = extractor.extract_dimensions(bitbucket_event)

        expect(extractor).to have_received(:extract_bitbucket_dimensions).with(bitbucket_event)
        expect(result).to eq({ test: "value" })
      end
    end

    context "with a CI event" do
      let(:ci_event) { FactoryBot.build(:event, name: "ci.build.completed", source: "jenkins") }

      it "delegates to extract_ci_dimensions" do
        allow(extractor).to receive(:extract_ci_dimensions).and_return({ test: "value" })

        result = extractor.extract_dimensions(ci_event)

        expect(extractor).to have_received(:extract_ci_dimensions).with(ci_event)
        expect(result).to eq({ test: "value" })
      end
    end

    context "with a Task event" do
      let(:task_event) { FactoryBot.build(:event, name: "task.created", source: "asana") }

      it "delegates to extract_task_dimensions" do
        allow(extractor).to receive(:extract_task_dimensions).and_return({ test: "value" })

        result = extractor.extract_dimensions(task_event)

        expect(extractor).to have_received(:extract_task_dimensions).with(task_event)
        expect(result).to eq({ test: "value" })
      end
    end

    context "with an unknown event source" do
      let(:unknown_event) { FactoryBot.build(:event, name: "unknown.event", source: "custom") }

      it "returns a basic dimension hash with source" do
        result = extractor.extract_dimensions(unknown_event)

        expect(result).to eq({ source: "custom" })
      end
    end
  end

  describe "#extract_github_dimensions" do
    let(:github_event) do
      FactoryBot.build(:event,
                       name: "github.push",
                       source: "github",
                       data: { repository: { full_name: "octocat/hello-world" } })
    end

    it "extracts repository name and organization" do
      dimensions = extractor.extract_github_dimensions(github_event)

      expect(dimensions[:repository]).to eq("octocat/hello-world")
      expect(dimensions[:organization]).to eq("octocat")
      expect(dimensions[:source]).to eq("github")
    end

    context "when repository info is missing" do
      let(:github_event_no_repo) { FactoryBot.build(:event, name: "github.push", source: "github", data: {}) }

      it "uses 'unknown' as fallback" do
        dimensions = extractor.extract_github_dimensions(github_event_no_repo)

        expect(dimensions[:repository]).to eq("unknown")
        expect(dimensions[:organization]).to eq("unknown")
        expect(dimensions[:source]).to eq("github")
      end
    end
  end

  describe "#extract_org_from_repo" do
    it "returns the organization part from a repo name" do
      org = extractor.extract_org_from_repo("octocat/hello-world")
      expect(org).to eq("octocat")
    end

    it "returns 'unknown' for nil repo name" do
      org = extractor.extract_org_from_repo(nil)
      expect(org).to eq("unknown")
    end
  end

  describe "#extract_commit_count" do
    let(:push_event) do
      FactoryBot.build(:event, data: { commits: [1, 2, 3] })
    end

    let(:event_no_commits) do
      FactoryBot.build(:event, data: {})
    end

    it "returns the count of commits" do
      count = extractor.extract_commit_count(push_event)
      expect(count).to eq(3)
    end

    it "returns 1 when no commits are present" do
      count = extractor.extract_commit_count(event_no_commits)
      expect(count).to eq(1)
    end
  end

  describe "#extract_author" do
    let(:event_with_sender) do
      FactoryBot.build(:event, data: { sender: { login: "octocat" } })
    end

    let(:event_with_pusher) do
      FactoryBot.build(:event, data: { pusher: { name: "octopus" } })
    end

    let(:event_no_author) do
      FactoryBot.build(:event, data: {})
    end

    it "extracts author from sender.login" do
      author = extractor.extract_author(event_with_sender)
      expect(author).to eq("octocat")
    end

    it "falls back to pusher.name if sender is missing" do
      author = extractor.extract_author(event_with_pusher)
      expect(author).to eq("octopus")
    end

    it "returns 'unknown' if no author info is available" do
      author = extractor.extract_author(event_no_author)
      expect(author).to eq("unknown")
    end
  end

  describe "#extract_branch" do
    let(:event_with_branch) do
      FactoryBot.build(:event, data: { ref: "refs/heads/main" })
    end

    let(:event_with_tag) do
      FactoryBot.build(:event, data: { ref: "refs/tags/v1.0.0" })
    end

    let(:event_no_ref) do
      FactoryBot.build(:event, data: {})
    end

    it "extracts branch name from refs/heads/" do
      branch = extractor.extract_branch(event_with_branch)
      expect(branch).to eq("main")
    end

    it "extracts tag name from refs/tags/" do
      branch = extractor.extract_branch(event_with_tag)
      expect(branch).to eq("v1.0.0")
    end

    it "returns 'unknown' if ref is missing" do
      branch = extractor.extract_branch(event_no_ref)
      expect(branch).to eq("unknown")
    end
  end
end
