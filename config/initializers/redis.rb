# frozen_string_literal: true

# Simplified Redis initializer - moved most functionality to Cache::RedisCache

Rails.logger.info "Initializing Redis..."

# Make sure core Redis gem is available
require "redis"
begin
  require "connection_pool"
rescue StandardError
  Rails.logger.error "Error initializing Redis: #{e.message}"
end
