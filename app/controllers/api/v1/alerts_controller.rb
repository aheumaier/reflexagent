module Api
  module V1
    class AlertsController < ApplicationController
      def index
        use_case = UseCaseFactory.create_list_alerts
        alerts = use_case.call(filter_params)

        render json: alerts.map(&:to_h)
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def show
        use_case = UseCaseFactory.create_find_alert
        alert = use_case.call(params[:id])

        if alert
          render json: alert.to_h
        else
          render json: { error: 'Alert not found' }, status: :not_found
        end
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def notify
        use_case = UseCaseFactory.create_send_notification
        use_case.call(params[:id])

        render json: { status: 'notification_sent', alert_id: params[:id] }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def filter_params
        params.permit(:severity, :source, :from_date, :to_date)
      end
    end
  end
end
