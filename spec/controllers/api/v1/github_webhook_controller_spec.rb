require 'rails_helper'

RSpec.describe Api::V1::GithubWebhookController, type: :controller do
  describe "POST #create" do
    let(:push_payload) do
      {
        "ref": "refs/heads/main",
        "commits": [
          {
            "id": "abc123def456",
            "message": "Fix bug in feature",
            "timestamp": "2023-01-02T12:34:56Z",
            "author": {
              "name": "Test User",
              "email": "test@example.com"
            },
            "url": "https://github.com/example/repo/commit/abc123def456"
          }
        ],
        "repository": {
          "id": 12345,
          "full_name": "example/repo",
          "private": false
        },
        "sender": {
          "login": "testuser"
        }
      }.to_json
    end

    let(:pull_request_payload) do
      {
        "action": "opened",
        "pull_request": {
          "number": 42,
          "title": "Add new feature",
          "user": {
            "login": "testuser"
          },
          "base": {
            "ref": "main",
            "sha": "abcdef123456"
          },
          "head": {
            "ref": "feature-branch",
            "sha": "123456abcdef"
          },
          "created_at": "2023-01-01T10:00:00Z",
          "updated_at": "2023-01-02T11:00:00Z",
          "merged": false,
          "merged_at": nil
        },
        "repository": {
          "id": 12345,
          "full_name": "example/repo",
          "private": false
        },
        "sender": {
          "login": "testuser"
        }
      }.to_json
    end

    let(:valid_signature) { 'sha256=valid_signature_hash' }
    let(:webhook_secret) { 'test_secret' }

    before do
      allow(Rails.application.credentials).to receive(:dig).with(:github, :webhook_secret).and_return(webhook_secret)
      # Stub the OpenSSL HMAC to return a predictable value for testing
      allow(OpenSSL::HMAC).to receive(:hexdigest).and_return('valid_signature_hash')

      # Stub the ProcessEvent use case
      allow(UseCaseFactory).to receive(:create_process_event).and_return(
        double('ProcessEvent', call: double('Event', id: 'test-event-id'))
      )

      request.headers['X-GitHub-Event'] = 'push'
      request.headers['X-Hub-Signature-256'] = valid_signature
    end

    context "with valid signature" do
      it "processes the webhook and returns 201" do
        post :create, body: push_payload, format: :json

        expect(response).to have_http_status(:created)
        parsed_response = JSON.parse(response.body)
        expect(parsed_response['status']).to eq('processed')
        expect(parsed_response).to have_key('id')
      end

      it "handles different GitHub event types" do
        request.headers['X-GitHub-Event'] = 'pull_request'

        post :create, body: pull_request_payload, format: :json

        expect(response).to have_http_status(:created)
        parsed_response = JSON.parse(response.body)
        expect(parsed_response['event_type']).to eq('pull_request')
      end
    end

    context "with invalid signature" do
      it "returns 401 unauthorized" do
        # Instead of stubbing the method, modify the request to trigger the validation failure
        request.headers['X-Hub-Signature-256'] = 'sha256=invalid_signature'

        post :create, body: push_payload, format: :json

        expect(response).to have_http_status(:unauthorized)
        parsed_response = JSON.parse(response.body)
        expect(parsed_response).to have_key('error')
      end
    end

    context "when an error occurs during processing" do
      before do
        allow(UseCaseFactory).to receive(:create_process_event).and_raise(StandardError.new("Test error"))
      end

      it "returns 422 with error message" do
        post :create, body: push_payload, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        parsed_response = JSON.parse(response.body)
        expect(parsed_response).to have_key('error')
      end
    end
  end
end
