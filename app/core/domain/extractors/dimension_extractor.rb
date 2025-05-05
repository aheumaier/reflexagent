# frozen_string_literal: true

module Domain
  module Extractors
    # DimensionExtractor is responsible for extracting dimension data from events
    # It provides methods for all supported event sources
    class DimensionExtractor
      # Extract appropriate dimensions for an event based on its source
      # @param event [Domain::Event] The event to extract dimensions from
      # @return [Hash] A hash of dimension key-value pairs
      def extract_dimensions(event)
        event_type = event.name

        case event_type
        when /^github\./
          extract_github_dimensions(event)
        when /^jira\./
          extract_jira_dimensions(event)
        when /^gitlab\./
          extract_gitlab_dimensions(event)
        when /^bitbucket\./
          extract_bitbucket_dimensions(event)
        when /^ci\./
          extract_ci_dimensions(event)
        when /^task\./
          extract_task_dimensions(event)
        else
          { source: event.source }
        end
      end

      # Extract GitHub event dimensions
      # @param event [Domain::Event] The GitHub event
      # @return [Hash] GitHub-specific dimensions
      def extract_github_dimensions(event)
        data = event.data
        {
          repository: data.dig(:repository, :full_name) || "unknown",
          organization: extract_org_from_repo(data.dig(:repository, :full_name)),
          source: event.source
        }
      end

      # Extract Jira event dimensions
      # @param event [Domain::Event] The Jira event
      # @return [Hash] Jira-specific dimensions
      def extract_jira_dimensions(event)
        data = event.data
        {
          project: data.dig(:issue, :fields, :project, :key) ||
            data.dig(:project, :key) ||
            "unknown",
          source: event.source
        }
      end

      # Extract GitLab event dimensions
      # @param event [Domain::Event] The GitLab event
      # @return [Hash] GitLab-specific dimensions
      def extract_gitlab_dimensions(event)
        data = event.data
        {
          project: data.dig(:project, :path_with_namespace) || "unknown",
          source: event.source
        }
      end

      # Extract Bitbucket event dimensions
      # @param event [Domain::Event] The Bitbucket event
      # @return [Hash] Bitbucket-specific dimensions
      def extract_bitbucket_dimensions(event)
        data = event.data
        {
          repository: data.dig(:repository, :full_name) || "unknown",
          source: event.source
        }
      end

      # Extract CI event dimensions
      # @param event [Domain::Event] The CI event
      # @return [Hash] CI-specific dimensions
      def extract_ci_dimensions(event)
        data = event.data
        {
          project: data[:project] || "unknown",
          provider: data[:provider] || "unknown",
          source: event.source
        }
      end

      # Extract Task event dimensions
      # @param event [Domain::Event] The Task event
      # @return [Hash] Task-specific dimensions
      def extract_task_dimensions(event)
        data = event.data
        {
          project: data[:project] || "unknown",
          task_type: data[:type] || "unknown",
          source: event.source
        }
      end

      # Helper method to extract the organization from a repository name
      # @param repo_name [String] The repository name (e.g., "org/repo")
      # @return [String] The organization name
      def extract_org_from_repo(repo_name)
        return "unknown" unless repo_name

        repo_name.split("/").first
      end

      # Helper method to extract commit count from a GitHub event
      # @param event [Domain::Event] The GitHub event
      # @return [Integer] The number of commits
      def extract_commit_count(event)
        event.data[:commits]&.size || 1
      end

      # Helper method to extract author from a GitHub event
      # @param event [Domain::Event] The GitHub event
      # @return [String] The author name or login
      def extract_author(event)
        event.data.dig(:sender, :login) ||
          event.data.dig(:pusher, :name) ||
          "unknown"
      end

      # Helper method to extract branch from a GitHub event
      # @param event [Domain::Event] The GitHub event
      # @return [String] The branch name
      def extract_branch(event)
        ref = event.data[:ref]
        return "unknown" unless ref

        # Remove refs/heads/ or refs/tags/ prefix
        ref.gsub(%r{^refs/(heads|tags)/}, "")
      end

      # Helper method to extract Jira issue type
      # @param event [Domain::Event] The Jira event
      # @return [String] The issue type
      def extract_jira_issue_type(event)
        event.data.dig(:issue, :fields, :issuetype, :name) || "unknown"
      end

      # Helper method to extract GitLab commit count
      # @param event [Domain::Event] The GitLab event
      # @return [Integer] The number of commits
      def extract_gitlab_commit_count(event)
        if event.data[:commits]
          event.data[:commits].size
        elsif event.data[:total_commits_count]
          event.data[:total_commits_count]
        else
          1
        end
      end

      # Helper method to extract Bitbucket commit count
      # @param event [Domain::Event] The Bitbucket event
      # @return [Integer] The number of commits
      def extract_bitbucket_commit_count(event)
        changes = event.data.dig(:push, :changes) || []
        changes.sum { |change| change.dig(:commits)&.size || 0 }
      end

      # Helper method to extract CI duration
      # @param event [Domain::Event] The CI event
      # @return [Integer] The duration in seconds
      def extract_ci_duration(event)
        # Duration in seconds
        data = event.data
        start_time = data[:start_time]
        end_time = data[:end_time]

        if start_time && end_time
          begin
            Time.parse(end_time) - Time.parse(start_time)
          rescue StandardError
            0
          end
        else
          data[:duration] || 0
        end
      end
    end
  end
end
