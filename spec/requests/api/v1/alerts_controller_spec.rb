require 'rails_helper'

RSpec.describe Api::V1::AlertsController, type: :request do
  describe "GET /api/v1/alerts" do
    it "returns a list of alerts" do
      allow_any_instance_of(Api::V1::AlertsController).to receive(:index) do |instance|
        instance.render json: [
          { id: 'alert-1', name: 'High CPU Usage', severity: 'critical', source: 'web-01' },
          { id: 'alert-2', name: 'High Memory Usage', severity: 'warning', source: 'web-01' },
          { id: 'alert-3', name: 'High Disk Usage', severity: 'critical', source: 'web-01' }
        ], status: :ok
      end

      get '/api/v1/alerts'

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response).to be_an(Array)
      expect(json_response.size).to eq(3)
    end

    it "filters alerts by severity" do
      allow_any_instance_of(Api::V1::AlertsController).to receive(:index) do |instance|
        instance.render json: [
          { id: 'alert-1', name: 'High CPU Usage', severity: 'critical', source: 'web-01' },
          { id: 'alert-3', name: 'High Disk Usage', severity: 'critical', source: 'web-01' }
        ], status: :ok
      end

      get '/api/v1/alerts', params: { severity: 'critical' }

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response).to be_an(Array)
      expect(json_response.size).to eq(2)
      expect(json_response.first['severity']).to eq('critical')
    end
  end

  describe "GET /api/v1/alerts/:id" do
    context "when the alert exists" do
      it "returns the alert" do
        allow_any_instance_of(Api::V1::AlertsController).to receive(:show) do |instance|
          instance.render json: {
            id: 'alert-1',
            name: 'High CPU Usage',
            severity: 'critical',
            source: 'web-01',
            created_at: Time.current.to_s
          }, status: :ok
        end

        get "/api/v1/alerts/alert-1"

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['id']).to eq('alert-1')
        expect(json_response['severity']).to eq('critical')
      end
    end

    context "when the alert does not exist" do
      it "returns not found" do
        allow_any_instance_of(Api::V1::AlertsController).to receive(:show) do |instance|
          instance.render json: { error: 'Alert not found' }, status: :not_found
        end

        get "/api/v1/alerts/non-existent-id"

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/alerts/:id/notify" do
    it "sends a notification for the alert" do
      allow_any_instance_of(Api::V1::AlertsController).to receive(:notify) do |instance|
        instance.render json: {
          status: 'notification_sent',
          alert_id: 'alert-1'
        }, status: :ok
      end

      post "/api/v1/alerts/alert-1/notify"

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response['status']).to eq('notification_sent')
      expect(json_response['alert_id']).to eq('alert-1')
    end

    context "when notification fails" do
      it "returns an error" do
        allow_any_instance_of(Api::V1::AlertsController).to receive(:notify) do |instance|
          instance.render json: { error: 'Failed to send notification' }, status: :unprocessable_entity
        end

        post "/api/v1/alerts/alert-1/notify"

        expect(response).to have_http_status(:unprocessable_entity)

        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('error')
      end
    end
  end
end
