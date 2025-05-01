class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:index]

  def index
    # Simple check to verify database connectivity
    ActiveRecord::Base.connection.execute("SELECT 1")

    # Check Redis if being used
    begin
      Redis.new(url: ENV.fetch("REDIS_URL", nil)).ping
      render json: { status: "ok", message: "All systems operational" }, status: :ok
    rescue StandardError => e
      render json: { status: "error", message: "Redis error: #{e.message}" }, status: :service_unavailable
    end
  end
end
