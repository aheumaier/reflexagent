# frozen_string_literal: true

module Domain
  module Constants
    # DimensionConstants module provides standardized constants for metric dimensions
    # This helps enforce consistent dimension naming across the application
    module DimensionConstants
      # Source dimensions identify the origin of metrics
      module Source
        REPOSITORY = "repository"
        ORGANIZATION = "organization"
        SOURCE = "source"
        PROJECT = "project"
        TEAM = "team"

        # All source dimensions
        ALL = [REPOSITORY, ORGANIZATION, SOURCE, PROJECT, TEAM].freeze
      end

      # Time dimensions provide temporal context
      module Time
        DATE = "date"
        TIMESTAMP = "timestamp"
        WEEK = "week"
        MONTH = "month"
        QUARTER = "quarter"
        COMMIT_DATE = "commit_date"
        DELIVERY_DATE = "delivery_date"

        # All time dimensions
        ALL = [DATE, TIMESTAMP, WEEK, MONTH, QUARTER, COMMIT_DATE, DELIVERY_DATE].freeze

        # Format a date according to our standards (YYYY-MM-DD)
        # @param date [Date, Time, String] The date to format
        # @return [String] Formatted date string
        def self.format_date(date)
          return nil unless date

          date_obj = date.is_a?(String) ? ::Time.parse(date) : date
          date_obj.strftime("%Y-%m-%d")
        rescue ArgumentError => e
          Rails.logger.error("Error formatting date: #{e.message}")
          nil
        end

        # Format a timestamp according to ISO 8601 (YYYY-MM-DDThh:mm:ssZ)
        # @param timestamp [Time, String] The timestamp to format
        # @return [String] Formatted timestamp string
        def self.format_timestamp(timestamp)
          return nil unless timestamp

          time_obj = timestamp.is_a?(String) ? ::Time.parse(timestamp) : timestamp
          time_obj.iso8601
        rescue ArgumentError => e
          Rails.logger.error("Error formatting timestamp: #{e.message}")
          nil
        end
      end

      # Actor dimensions identify people involved
      module Actor
        AUTHOR = "author"
        REVIEWER = "reviewer"
        ASSIGNEE = "assignee"
        COMMITTER = "committer"
        REQUESTOR = "requestor"

        # All actor dimensions
        ALL = [AUTHOR, REVIEWER, ASSIGNEE, COMMITTER, REQUESTOR].freeze
      end

      # Content dimensions describe what is being measured
      module Content
        BRANCH = "branch"
        DIRECTORY = "directory"
        FILETYPE = "filetype"
        ENVIRONMENT = "environment"
        COMPONENT = "component"
        LABELS = "labels"

        # All content dimensions
        ALL = [BRANCH, DIRECTORY, FILETYPE, ENVIRONMENT, COMPONENT, LABELS].freeze

        # Format a branch name according to standards
        # @param branch_name [String] The raw branch name
        # @param type [Symbol] Optional type (:branch, :tag, :pr)
        # @return [String] Formatted branch name
        def self.format_branch(branch_name, type = :branch)
          return "unknown" unless branch_name.present?

          case type
          when :tag
            "tag:#{branch_name}"
          when :pr
            "pr:#{branch_name}"
          else
            branch_name
          end
        end
      end

      # Classification dimensions categorize metrics
      module Classification
        TYPE = "type"
        SCOPE = "scope"
        PRIORITY = "priority"
        SEVERITY = "severity"
        STATUS = "status"
        ACTION = "action"
        CONCLUSION = "conclusion"
        CONVENTIONAL = "conventional"

        # All classification dimensions
        ALL = [TYPE, SCOPE, PRIORITY, SEVERITY, STATUS, ACTION, CONCLUSION, CONVENTIONAL].freeze

        # Format a boolean value consistently as a string
        # @param value [Boolean, String, Integer] The boolean value to format
        # @return [String] "true" or "false"
        def self.format_boolean(value)
          case value
          when true, "true", "yes", "1", 1
            "true"
          else
            "false"
          end
        end
      end

      # Measurement dimensions provide context for measured values
      module Measurement
        UNIT = "unit"
        AGGREGATION = "aggregation"
        INTERVAL = "interval"
        BASELINE = "baseline"

        # All measurement dimensions
        ALL = [UNIT, AGGREGATION, INTERVAL, BASELINE].freeze
      end

      # Helper to get all dimension names
      # @return [Array<String>] All dimension names
      def self.all_dimensions
        Source::ALL + Time::ALL + Actor::ALL + Content::ALL + Classification::ALL + Measurement::ALL
      end

      # Helper to validate a dimension name
      # @param name [String] The dimension name to validate
      # @return [Boolean] Whether the dimension name is valid
      def self.valid_dimension?(name)
        all_dimensions.include?(name)
      end

      # Helper to normalize repository names
      # @param repository [String] The repository name to normalize
      # @return [String] Normalized repository name
      def self.normalize_repository(repository)
        return "unknown" unless repository.present?

        # Ensure format is organization/repository
        if repository.include?("/")
          repository
        else
          "unknown/#{repository}"
        end
      end

      # Helper to build standard dimensions hash for a metric
      # @param source [String] Source system (github, jira, etc.)
      # @param repository [String] Repository name
      # @param organization [String] Organization name
      # @param author [String] Author name
      # @param additional_dimensions [Hash] Additional dimensions to include
      # @return [Hash] Combined dimensions hash
      def self.build_standard_dimensions(
        source:,
        repository: nil,
        organization: nil,
        author: nil,
        additional_dimensions: {}
      )
        dimensions = {
          Source::SOURCE => source
        }

        # Add repository if present
        if repository.present?
          normalized_repo = normalize_repository(repository)
          dimensions[Source::REPOSITORY] = normalized_repo

          # Extract organization from repository if not provided
          if organization.nil? && normalized_repo.include?("/")
            dimensions[Source::ORGANIZATION] = normalized_repo.split("/").first
          end
        end

        # Add organization if provided
        dimensions[Source::ORGANIZATION] = organization if organization.present?

        # Add author if provided
        dimensions[Actor::AUTHOR] = author if author.present?

        # Add current date if not in additional dimensions
        dimensions[Time::DATE] = Time.format_date(::Time.now) unless additional_dimensions.key?(Time::DATE)

        # Merge additional dimensions
        dimensions.merge!(additional_dimensions)

        dimensions
      end
    end
  end
end
