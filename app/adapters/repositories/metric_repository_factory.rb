# frozen_string_literal: true

module Repositories
  # MetricRepositoryFactory provides a central way to create repository instances
  # with proper dependency injection. It caches instances for reuse and provides
  # a clean API for getting the right repository type.
  class MetricRepositoryFactory
    # Initialize the factory with optional dependencies
    # @param metric_naming_port [Object] Implementation of MetricNamingPort
    # @param logger_port [Object] Implementation of LoggerPort
    def initialize(metric_naming_port: nil, logger_port: nil)
      @metric_naming_port = metric_naming_port || (if defined?(Adapters::Metrics::MetricNamingAdapter)
                                                     Adapters::Metrics::MetricNamingAdapter.new
                                                   else
                                                     nil
                                                   end)
      @logger_port = logger_port || Rails.logger
      @repository_cache = {}
    end

    # Get a BaseMetricRepository instance
    # @return [Repositories::BaseMetricRepository]
    def base_repository
      get_repository(:base)
    end

    # Get a GitMetricRepository instance
    # @return [Repositories::GitMetricRepository]
    def git_repository
      get_repository(:git)
    end

    # Get a DoraMetricsRepository instance
    # @return [Repositories::DoraMetricsRepository]
    def dora_repository
      get_repository(:dora)
    end

    # Get an IssueMetricRepository instance
    # @return [Repositories::IssueMetricRepository]
    def issue_repository
      get_repository(:issue)
    end

    # Get the legacy MetricRepository instance
    # @return [Repositories::MetricRepository]
    def legacy_repository
      get_repository(:legacy)
    end

    # Get a repository by name
    # @param name [Symbol] Repository name (:base, :git, :dora, :issue, :legacy)
    # @return [Object] Repository instance
    # @raise [ArgumentError] If repository name is not recognized
    def repository(name)
      get_repository(name)
    end

    # Clear the repository cache
    # Useful in testing or when dependencies change
    def clear_cache
      @repository_cache = {}
      nil
    end

    private

    # Get or create a repository instance from the cache
    # @param type [Symbol] Repository type
    # @return [Object] Repository instance
    def get_repository(type)
      return @repository_cache[type] if @repository_cache[type]

      @repository_cache[type] = create_repository(type)
    end

    # Create a new repository instance based on type
    # @param type [Symbol] Repository type
    # @return [Object] Repository instance
    # @raise [ArgumentError] If repository type is not recognized
    def create_repository(type)
      case type
      when :base
        BaseMetricRepository.new(
          metric_naming_port: @metric_naming_port,
          logger_port: @logger_port
        )
      when :git
        GitMetricRepository.new(
          metric_naming_port: @metric_naming_port,
          logger_port: @logger_port
        )
      when :dora
        DoraMetricsRepository.new(
          metric_naming_port: @metric_naming_port,
          logger_port: @logger_port
        )
      when :issue
        IssueMetricRepository.new(
          metric_naming_port: @metric_naming_port,
          logger_port: @logger_port
        )
      when :legacy
        MetricRepository.new(
          logger_port: @logger_port
        )
      else
        raise ArgumentError, "Unknown repository type: #{type}"
      end
    end
  end
end
