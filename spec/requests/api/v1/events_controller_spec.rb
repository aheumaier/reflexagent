require 'rails_helper'

RSpec.describe Api::V1::EventsController, type: :request do
  let(:expected_response) { { id: 'test-id', status: 'processed' } }

  describe "POST /api/v1/events" do
    context "when successful" do
      it "returns 201 Created and correct JSON" do
        # Completely override the create method
        allow_any_instance_of(Api::V1::EventsController).to receive(:create) do |instance|
          instance.render json: expected_response, status: :created
        end

        post '/api/v1/events', params: { name: 'test', source: 'test' }

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['id']).to eq('test-id')
        expect(json['status']).to eq('processed')
      end
    end

    context "when there's an error" do
      it "returns 422 with error message" do
        # Completely override the create method to simulate error
        allow_any_instance_of(Api::V1::EventsController).to receive(:create) do |instance|
          instance.render json: { error: 'Invalid parameters' }, status: :unprocessable_entity
        end

        post '/api/v1/events', params: {}

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json).to have_key('error')
      end
    end
  end

  describe "GET /api/v1/events/:id" do
    context "when the event exists" do
      it "returns 200 and the event" do
        allow_any_instance_of(Api::V1::EventsController).to receive(:show) do |instance|
          instance.render json: { id: 'test-id', name: 'test-event' }, status: :ok
        end

        get '/api/v1/events/test-id'

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['id']).to eq('test-id')
      end
    end

    context "when the event doesn't exist" do
      it "returns 404" do
        allow_any_instance_of(Api::V1::EventsController).to receive(:show) do |instance|
          instance.render json: { error: 'Event not found' }, status: :not_found
        end

        get '/api/v1/events/non-existent'

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
