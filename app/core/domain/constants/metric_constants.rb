# frozen_string_literal: true

module Domain
  module Constants
    # MetricNames module provides standardized constants for metric naming
    # This helps enforce consistent naming patterns across the application
    module MetricNames
      # Source systems that generate events
      module Sources
        GITHUB = "github"
        BITBUCKET = "bitbucket"
        JIRA = "jira"
        GITLAB = "gitlab"
        AZURE = "azure"
        JENKINS = "jenkins"
        TEAMCITY = "teamcity"

        # Cross-source metrics
        DORA = "dora"

        # All valid sources
        ALL = [GITHUB, BITBUCKET, JIRA, GITLAB, AZURE, JENKINS, TEAMCITY, DORA].freeze
      end

      # Entity categories that metrics measure
      module Entities
        # Git-related entities
        PUSH = "push"
        COMMIT = "commit"
        BRANCH = "branch"
        TAG = "tag"

        # Code review entities
        PULL_REQUEST = "pull_request"
        MERGE_REQUEST = "merge_request"
        REVIEW = "review"
        COMMENT = "comment"

        # Issue tracking entities
        ISSUE = "issue"
        BUG = "bug"
        STORY = "story"
        TASK = "task"
        EPIC = "epic"

        # CI/CD entities
        BUILD = "build"
        TEST = "test"
        DEPLOY = "deploy"
        RELEASE = "release"
        PIPELINE = "pipeline"
        WORKFLOW = "workflow"
        WORKFLOW_JOB = "workflow_job"
        WORKFLOW_STEP = "workflow_step"

        # Repository entities
        REPOSITORY = "repository"
        PROJECT = "project"

        # CI category
        CI = "ci"

        # Deployment entities
        DEPLOYMENT = "deployment"
        DEPLOYMENT_STATUS = "deployment_status"

        # Check entities
        CHECK_RUN = "check_run"
        CHECK_SUITE = "check_suite"

        # All valid entities
        ALL = [
          PUSH, COMMIT, BRANCH, TAG,
          PULL_REQUEST, MERGE_REQUEST, REVIEW, COMMENT,
          ISSUE, BUG, STORY, TASK, EPIC,
          BUILD, TEST, DEPLOY, RELEASE, PIPELINE, WORKFLOW, WORKFLOW_JOB, WORKFLOW_STEP,
          REPOSITORY, PROJECT, CI, DEPLOYMENT, DEPLOYMENT_STATUS,
          CHECK_RUN, CHECK_SUITE
        ].freeze
      end

      # Actions performed on entities
      module Actions
        # Counting actions
        TOTAL = "total"
        COUNT = "count"

        # State change actions
        CREATED = "created"
        UPDATED = "updated"
        DELETED = "deleted"
        OPENED = "opened"
        CLOSED = "closed"
        MERGED = "merged"

        # Result actions
        SUCCESS = "success"
        FAILURE = "failure"
        ERROR = "error"
        COMPLETED = "completed"
        INCIDENT = "incident"

        # Timing actions
        DURATION = "duration"
        LEAD_TIME = "lead_time"
        TIME_TO_MERGE = "time_to_merge"
        TIME_TO_CLOSE = "time_to_close"

        # Stat actions
        ADDITIONS = "additions"
        DELETIONS = "deletions"
        CHURN = "churn"
        SIZE = "size"
        COMPLEXITY = "complexity"

        # Specific GitHub actions
        COMMITS = "commits"
        FILES_ADDED = "files_added"
        FILES_MODIFIED = "files_modified"
        FILES_REMOVED = "files_removed"
        DIRECTORY_CHANGES = "directory_changes"
        DIRECTORY_HOTSPOT = "directory_hotspot"
        FILETYPE_CHANGES = "filetype_changes"
        FILETYPE_HOTSPOT = "filetype_hotspot"
        CODE_ADDITIONS = "code_additions"
        CODE_DELETIONS = "code_deletions"
        CODE_CHURN = "code_churn"
        BRANCH_ACTIVITY = "branch_activity"
        BY_AUTHOR = "by_author"
        ENVIRONMENT = "environment"
        CONCLUSION = "conclusion"
        REGISTRATION_EVENT = "registration_event"

        # All valid actions
        ALL = [
          TOTAL, COUNT,
          CREATED, UPDATED, DELETED, OPENED, CLOSED, MERGED,
          SUCCESS, FAILURE, ERROR, COMPLETED, INCIDENT,
          DURATION, LEAD_TIME, TIME_TO_MERGE, TIME_TO_CLOSE,
          ADDITIONS, DELETIONS, CHURN, SIZE, COMPLEXITY,
          COMMITS, FILES_ADDED, FILES_MODIFIED, FILES_REMOVED,
          DIRECTORY_CHANGES, DIRECTORY_HOTSPOT, FILETYPE_CHANGES, FILETYPE_HOTSPOT,
          CODE_ADDITIONS, CODE_DELETIONS, CODE_CHURN, BRANCH_ACTIVITY,
          BY_AUTHOR, ENVIRONMENT, CONCLUSION, REGISTRATION_EVENT
        ].freeze
      end

      # Details for additional context
      module Details
        # Time-based details
        DAILY = "daily"
        WEEKLY = "weekly"
        MONTHLY = "monthly"
        QUARTERLY = "quarterly"

        # Count details
        TOTAL = "total"

        # All valid details
        ALL = [DAILY, WEEKLY, MONTHLY, QUARTERLY, TOTAL].freeze
      end

      # DORA Metrics
      module DoraMetrics
        DEPLOYMENT_FREQUENCY = "dora.deployment_frequency"
        LEAD_TIME = "dora.lead_time"
        TIME_TO_RESTORE = "dora.time_to_restore"
        CHANGE_FAILURE_RATE = "dora.change_failure_rate"

        ALL = [DEPLOYMENT_FREQUENCY, LEAD_TIME, TIME_TO_RESTORE, CHANGE_FAILURE_RATE].freeze
      end

      # Helper method to build metric names
      # @param source [String] The source system (e.g., github, jira)
      # @param entity [String] The entity being measured (e.g., push, issue)
      # @param action [String] The action (e.g., total, created)
      # @param detail [String, nil] Optional detail (e.g., daily, by_author)
      # @return [String] The formatted metric name
      def self.build(source:, entity:, action:, detail: nil)
        segments = [source, entity, action]
        segments << detail if detail.present?
        segments.join(".")
      end

      # Validates a metric name against the convention
      # @param name [String] The metric name to validate
      # @return [Boolean] Whether the name is valid
      def self.valid?(name)
        parts = name.split(".")
        return false if parts.size < 3 || parts.size > 4

        source, entity, action, detail = parts

        return false unless Sources::ALL.include?(source)
        return false unless Entities::ALL.include?(entity)
        return false unless Actions::ALL.include?(action)
        return false if detail && !Details::ALL.include?(detail)

        true
      end
    end
  end
end
