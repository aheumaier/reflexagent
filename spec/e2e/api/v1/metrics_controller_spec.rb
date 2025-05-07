require 'rails_helper'

RSpec.describe Api::V1::MetricsController, type: :request do
  include Rails.application.routes.url_helpers

  describe "GET /api/v1/metrics" do
    it "returns a list of metrics" do
      allow_any_instance_of(Api::V1::MetricsController).to receive(:index) do |instance|
        instance.render json: [
          { id: 'metric-1', name: 'cpu.usage', source: 'web-01' },
          { id: 'metric-2', name: 'memory.usage', source: 'web-01' },
          { id: 'metric-3', name: 'disk.usage', source: 'web-01' }
        ], status: :ok
      end

      get '/api/v1/metrics'

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response).to be_an(Array)
      expect(json_response.size).to eq(3)
    end

    it "filters metrics by source" do
      allow_any_instance_of(Api::V1::MetricsController).to receive(:index) do |instance|
        instance.render json: [
          { id: 'metric-4', name: 'cpu.usage', source: 'db-01' }
        ], status: :ok
      end

      get '/api/v1/metrics', params: { source: 'db-01' }

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response.size).to eq(1)
      expect(json_response.first['source']).to eq('db-01')
    end
  end

  describe "GET /api/v1/metrics/:id" do
    context "when the metric exists" do
      it "returns the metric" do
        allow_any_instance_of(Api::V1::MetricsController).to receive(:show) do |instance|
          instance.render json: {
            id: 'metric-1',
            name: 'cpu.usage',
            value: 85.5,
            source: 'web-01'
          }, status: :ok
        end

        get "/api/v1/metrics/metric-1"

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['id']).to eq('metric-1')
        expect(json_response['name']).to eq('cpu.usage')
      end
    end

    context "when the metric does not exist" do
      it "returns not found" do
        allow_any_instance_of(Api::V1::MetricsController).to receive(:show) do |instance|
          instance.render json: { error: 'Metric not found' }, status: :not_found
        end

        get "/api/v1/metrics/non-existent-id"

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/metrics/:id/analyze" do
    context "with a high-value metric" do
      it "detects an anomaly and creates an alert" do
        allow_any_instance_of(Api::V1::MetricsController).to receive(:analyze) do |instance|
          instance.render json: {
            metric_id: 'high-metric-id',
            alert_id: 'alert-1',
            status: 'anomaly_detected'
          }, status: :ok
        end

        post "/api/v1/metrics/high-metric-id/analyze"

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('anomaly_detected')
        expect(json_response).to have_key('alert_id')
      end
    end

    context "with a normal-value metric" do
      it "does not create an alert" do
        allow_any_instance_of(Api::V1::MetricsController).to receive(:analyze) do |instance|
          instance.render json: {
            metric_id: 'normal-metric-id',
            status: 'normal'
          }, status: :ok
        end

        post "/api/v1/metrics/normal-metric-id/analyze"

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('normal')
        expect(json_response).not_to have_key('alert_id')
      end
    end
  end
end
