# frozen_string_literal: true

module Ports
  # MetricNamingPort defines the interface for translating domain events into standardized metric names
  # This port serves as a contract between the core domain and adapters that implement metric naming
  module MetricNamingPort
    # Build a standardized metric name following the [source].[entity].[action].[detail] convention
    # @param source [String] The source system generating the event (github, bitbucket, etc.)
    # @param entity [String] The primary object being measured (push, pull_request, etc.)
    # @param action [String] The specific operation on the entity (total, created, etc.)
    # @param detail [String, nil] Optional additional context (daily, by_author, etc.)
    # @return [String] The formatted metric name
    def build_metric_name(source:, entity:, action:, detail: nil)
      raise NotImplementedError, "#{self.class} must implement #build_metric_name"
    end

    # Validate if a metric name follows the standardized naming convention
    # @param name [String] The metric name to validate
    # @return [Boolean] Whether the name is valid according to convention
    def valid_metric_name?(name)
      raise NotImplementedError, "#{self.class} must implement #valid_metric_name?"
    end

    # Extract standard components from a metric name
    # @param name [String] The metric name to parse
    # @return [Hash] Hash with :source, :entity, :action, and optional :detail keys
    def parse_metric_name(name)
      raise NotImplementedError, "#{self.class} must implement #parse_metric_name"
    end

    # Build standard dimensions for a metric based on event data
    # @param event [Domain::Event] The event to extract dimensions from
    # @param additional_dimensions [Hash] Additional dimensions to include
    # @return [Hash] Normalized dimensions following standards
    def build_standard_dimensions(event, additional_dimensions = {})
      raise NotImplementedError, "#{self.class} must implement #build_standard_dimensions"
    end

    # Normalize a dimension name according to standards
    # @param name [String] Raw dimension name to normalize
    # @return [String] Standardized dimension name
    def normalize_dimension_name(name)
      raise NotImplementedError, "#{self.class} must implement #normalize_dimension_name"
    end

    # Normalize a dimension value according to standards
    # @param dimension [String] The dimension name
    # @param value [Object] The dimension value to normalize
    # @return [String, Numeric] Normalized dimension value
    def normalize_dimension_value(dimension, value)
      raise NotImplementedError, "#{self.class} must implement #normalize_dimension_value"
    end

    # Check if a dimension name is valid according to standards
    # @param name [String] The dimension name to validate
    # @return [Boolean] Whether the dimension name is valid
    def valid_dimension_name?(name)
      raise NotImplementedError, "#{self.class} must implement #valid_dimension_name?"
    end

    # Get all available source systems
    # @return [Array<String>] List of valid source system names
    def available_sources
      raise NotImplementedError, "#{self.class} must implement #available_sources"
    end

    # Get all valid entity names
    # @return [Array<String>] List of valid entity names
    def available_entities
      raise NotImplementedError, "#{self.class} must implement #available_entities"
    end

    # Get all valid action names
    # @return [Array<String>] List of valid action names
    def available_actions
      raise NotImplementedError, "#{self.class} must implement #available_actions"
    end

    # Get all valid detail suffixes
    # @return [Array<String>] List of valid detail suffixes
    def available_details
      raise NotImplementedError, "#{self.class} must implement #available_details"
    end

    # Get all standard dimension categories
    # @return [Array<String>] List of dimension categories (source, time, actor, etc.)
    def dimension_categories
      raise NotImplementedError, "#{self.class} must implement #dimension_categories"
    end

    # Get all dimensions in a specific category
    # @param category [String] The dimension category
    # @return [Array<String>] List of dimensions in the category
    def dimensions_in_category(category)
      raise NotImplementedError, "#{self.class} must implement #dimensions_in_category"
    end

    # Check if a proposed metric name mapping is valid (for migrations)
    # @param old_name [String] The old metric name
    # @param new_name [String] The proposed standardized name
    # @return [Boolean] Whether the mapping is valid
    def valid_metric_mapping?(old_name, new_name)
      raise NotImplementedError, "#{self.class} must implement #valid_metric_mapping?"
    end
  end
end
