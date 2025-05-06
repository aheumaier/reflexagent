require "rails_helper"

RSpec.describe Web::WebAdapter do
  let(:adapter) { described_class.new }

  describe "#receive_event" do
    context "with a GitHub commit payload" do
      let(:github_commit_payload) do
        {
          ref: "refs/heads/main",
          before: "6113728f27ae82c7b1a177c8d03f9e96e0adf246",
          after: "59b20b8d5c6ff8d09518216e87bc7ec123a3250a",
          repository: {
            id: 123_456,
            name: "ReflexAgent",
            full_name: "octocat/ReflexAgent",
            owner: {
              name: "octocat",
              email: "octocat@github.com"
            }
          },
          pusher: {
            name: "octocat",
            email: "octocat@github.com"
          },
          commits: [
            {
              id: "59b20b8d5c6ff8d09518216e87bc7ec123a3250a",
              message: "Add new feature for metric calculation",
              timestamp: "2023-06-15T12:00:00Z",
              author: {
                name: "Octocat",
                email: "octocat@github.com"
              }
            }
          ]
        }.to_json
      end

      it "correctly parses and creates a domain event" do
        # Allow time to be consistent in tests
        frozen_time = Time.new(2023, 6, 16, 10, 0, 0)
        allow(Time).to receive(:current).and_return(frozen_time)

        # Process the event
        event = adapter.receive_event(github_commit_payload, source: "github")

        # Verify the returned event
        expect(event).to be_a(Domain::Event)
        expect(event.source).to eq("github")
        expect(event.name).to eq("github.push") # Commits array indicates it's a push event
        expect(event.timestamp).to eq(frozen_time)

        # Verify the parsed data
        expect(event.data[:repository][:full_name]).to eq("octocat/ReflexAgent")
        expect(event.data[:commits].first[:message]).to eq("Add new feature for metric calculation")
      end

      it "extracts commit info from a GitHub push event" do
        # GitHub push events have specific fields we care about
        push_payload = JSON.parse(github_commit_payload)
        push_payload["action"] = "push"

        # Process the event with the updated payload
        event = adapter.receive_event(push_payload.to_json, source: "github")

        # The event name should include the action
        expect(event.name).to eq("github.push")
      end
    end

    context "with a GitHub pull request payload" do
      let(:github_pr_payload) do
        {
          action: "opened",
          number: 123,
          pull_request: {
            id: 456_789,
            title: "Add new metrics calculation algorithm",
            body: "This PR implements the new algorithm discussed in #42",
            user: {
              login: "octocat",
              id: 123_456
            },
            head: {
              ref: "feature-branch",
              sha: "6dcb09b5b57875f334f61aebed695e2e4193db5e"
            },
            base: {
              ref: "main",
              sha: "6dcb09b5b57875f334f61aebed695e2e4193db5e"
            }
          },
          repository: {
            id: 123_456,
            name: "ReflexAgent",
            full_name: "octocat/ReflexAgent"
          }
        }.to_json
      end

      it "correctly parses a pull request event" do
        event = adapter.receive_event(github_pr_payload, source: "github")

        expect(event).to be_a(Domain::Event)
        expect(event.source).to eq("github")
        expect(event.name).to eq("github.pull_request.opened")
        expect(event.data[:pull_request][:title]).to eq("Add new metrics calculation algorithm")
      end
    end

    context "with invalid JSON" do
      it "raises an InvalidPayloadError" do
        expect do
          adapter.receive_event("invalid json", source: "github")
        end.to raise_error(Web::WebAdapter::InvalidPayloadError)
      end
    end

    context "with different webhook sources" do
      it "handles Jira payloads" do
        jira_payload = {
          webhookEvent: "jira:issue_updated",
          issue: {
            key: "PROJ-123",
            fields: {
              summary: "Improve error handling",
              status: { name: "In Progress" }
            }
          }
        }.to_json

        event = adapter.receive_event(jira_payload, source: "jira")

        expect(event).to be_a(Domain::Event)
        expect(event.source).to eq("jira")
        expect(event.name).to eq("jira.jira:issue_updated")
      end

      it "handles GitLab payloads" do
        gitlab_payload = {
          object_kind: "push",
          project: {
            id: 123,
            name: "ReflexAgent",
            path_with_namespace: "company/reflexagent"
          }
        }.to_json

        event = adapter.receive_event(gitlab_payload, source: "gitlab")

        expect(event).to be_a(Domain::Event)
        expect(event.source).to eq("gitlab")
        expect(event.name).to eq("gitlab.push")
      end

      it "handles unknown sources with a generic approach" do
        custom_payload = {
          type: "custom_event",
          data: {
            key: "value"
          }
        }.to_json

        event = adapter.receive_event(custom_payload, source: "custom_source")

        expect(event).to be_a(Domain::Event)
        expect(event.source).to eq("custom_source")
        expect(event.name).to eq("custom_source.custom_event")
      end
    end
  end
end
