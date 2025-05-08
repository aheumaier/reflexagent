# frozen_string_literal: true

require "rails_helper"
require_relative "../../app/adapters/web/web_adapter"
require_relative "../../app/adapters/repositories/event_repository"
require_relative "../../app/adapters/repositories/team_repository"
require_relative "../../app/adapters/queuing/sidekiq_queue_adapter"
require_relative "../../app/adapters/cache/redis_cache"

# Helper module for integration tests that need to use use cases
module UseCaseTestHelpers
  # Get process_event_use_case for integration tests
  # This preserves the same configuration as was previously registered in the container
  def get_process_event_use_case
    # For integration tests, we need real adapters
    UseCases::ProcessEvent.new(
      ingestion_port: get_port(:ingestion_port, Web::WebAdapter.new),
      storage_port: get_port(:event_repository, Repositories::EventRepository.new),
      queue_port: get_port(:queue_port, Queuing::SidekiqQueueAdapter.new),
      team_repository_port: get_port(:team_repository, Repositories::TeamRepository.new),
      logger_port: Rails.logger
    )
  end

  # Get register_repository_use_case for integration tests
  def get_register_repository_use_case
    UseCases::RegisterRepository.new(
      team_repository_port: get_port(:team_repository, Repositories::TeamRepository.new),
      logger_port: Rails.logger
    )
  end

  # Get list_team_repositories_use_case for integration tests
  def get_list_team_repositories_use_case
    UseCases::ListTeamRepositories.new(
      team_repository_port: get_port(:team_repository, Repositories::TeamRepository.new),
      cache_port: get_port(:cache_port, Cache::RedisCache.new),
      logger_port: Rails.logger
    )
  end

  # Get find_or_create_team_use_case for integration tests
  def get_find_or_create_team_use_case
    UseCases::FindOrCreateTeam.new(
      team_repository_port: get_port(:team_repository, Repositories::TeamRepository.new),
      logger_port: Rails.logger
    )
  end

  private

  # Helper method to safely get port from container or create new if not available
  def get_port(port_name, default_adapter)
    DependencyContainer.resolve(port_name)
  rescue StandardError => e
    Rails.logger.warn "Port #{port_name} not found in container, using default adapter: #{e.message}"
    default_adapter
  end
end
