# frozen_string_literal: true

class HealthController < ApplicationController
  # Skip any authentication
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  # Basic health check endpoint
  def index
    render json: {
      status: "ok",
      version: app_version,
      timestamp: Time.current.iso8601,
      environment: Rails.env,
      database: database_status,
      redis: redis_status,
      sidekiq: sidekiq_status
    }
  end

  private

  def app_version
    # Try different ways to get the version
    return ENV["APP_VERSION"] if ENV["APP_VERSION"].present?
    return Rails.application.config.version if Rails.application.config.respond_to?(:version)
    return Rails.application.engine_version.to_s if Rails.application.respond_to?(:engine_version)

    "unknown"
  end

  def database_status
    ActiveRecord::Base.connection.execute("SELECT 1")
    "ok"
  rescue StandardError => e
    "error: #{e.message}"
  end

  def redis_status
    Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0")).ping == "PONG" ? "ok" : "error"
  rescue StandardError => e
    "error: #{e.message}"
  end

  def sidekiq_status
    stats = Sidekiq::Stats.new
    {
      processed: stats.processed,
      failed: stats.failed,
      queues: stats.queues,
      workers: Sidekiq::ProcessSet.new.size,
      status: "ok"
    }
  rescue StandardError => e
    { status: "error: #{e.message}" }
  end
end
