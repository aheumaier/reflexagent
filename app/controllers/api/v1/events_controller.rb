module Api
  module V1
    class EventsController < ApplicationController
      skip_before_action :verify_authenticity_token

      def create
        event = Core::Domain::Event.new(
          name: params[:name],
          data: event_params[:data],
          source: params[:source],
          timestamp: Time.current
        )

        use_case = UseCaseFactory.create_process_event
        processed_event = use_case.call(event)

        # Enqueue metric calculation job
        MetricCalculationJob.perform_async(processed_event.id)

        render json: { id: processed_event.id, status: 'processed' }, status: :created
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def show
        use_case = UseCaseFactory.create_find_event
        event = use_case.call(params[:id])

        if event
          render json: event.to_h
        else
          render json: { error: 'Event not found' }, status: :not_found
        end
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def event_params
        params.permit(:name, :source, data: {})
      end
    end
  end
end
