module Api
  module V1
    class MetricsController < ApplicationController
      def index
        use_case = UseCaseFactory.create_list_metrics
        metrics = use_case.call(filter_params)

        render json: metrics.map(&:to_h)
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def show
        use_case = UseCaseFactory.create_find_metric
        metric = use_case.call(params[:id])

        if metric
          render json: metric.to_h
        else
          render json: { error: "Metric not found" }, status: :not_found
        end
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def analyze
        use_case = UseCaseFactory.create_detect_anomalies
        alert = use_case.call(params[:id])

        if alert
          render json: {
            metric_id: params[:id],
            alert_id: alert.id,
            status: "anomaly_detected"
          }, status: :ok
        else
          render json: {
            metric_id: params[:id],
            status: "normal"
          }, status: :ok
        end
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def filter_params
        params.permit(:source, :name, :from_date, :to_date)
      end
    end
  end
end
