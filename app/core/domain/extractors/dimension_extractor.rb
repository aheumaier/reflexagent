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

      # Extract commit message components using conventional commit format
      # @param commit [Hash] A single commit from the payload
      # @return [Hash] Parsed components (type, scope, description)
      def extract_conventional_commit_parts(commit)
        message = commit[:message] || ""

        # Match conventional commit format: type(scope): description
        # Fix the regex by avoiding character class issues with forward slash
        if message.match?(/^(\w+)(\([^)]+\))?!?: (.+)/)
          matches = message.match(/^(\w+)(\([^)]+\))?!?: (.+)/)
          type = matches[1]
          scope = matches[2] ? matches[2].gsub(/[\(\)]/, "") : nil
          description = matches[3]
          breaking = message.include?("!")

          {
            commit_type: type,
            commit_scope: scope,
            commit_description: description,
            commit_breaking: breaking,
            commit_conventional: true
          }
        else
          {
            commit_description: message,
            commit_conventional: false
          }
        end
      end

      # Extract modified files from a commit or push event
      # @param event [Domain::Event] The GitHub event
      # @return [Hash] File statistics by category
      def extract_file_changes(event)
        # For individual commits
        if event.data[:commits]
          file_stats = { added: [], modified: [], removed: [] }

          event.data[:commits].each do |commit|
            file_stats[:added].concat(commit[:added] || [])
            file_stats[:modified].concat(commit[:modified] || [])
            file_stats[:removed].concat(commit[:removed] || [])
          end

          # Store the full lists for detailed analysis
          result = {
            files_added: file_stats[:added].size,
            files_modified: file_stats[:modified].size,
            files_removed: file_stats[:removed].size,

            # Full file lists (for detailed analysis)
            file_paths_added: file_stats[:added],
            file_paths_modified: file_stats[:modified],
            file_paths_removed: file_stats[:removed]
          }

          # Add directory and extension analytics
          directory_stats = analyze_directories(file_stats[:added] + file_stats[:modified] + file_stats[:removed])
          extension_stats = analyze_extensions(file_stats[:added] + file_stats[:modified] + file_stats[:removed])

          result.merge!(directory_stats).merge!(extension_stats)
        else
          # Handle other events that might contain file changes differently
          {
            files_added: 0,
            files_modified: 0,
            files_removed: 0
          }
        end
      end

      # Analyze directories for a list of files with full path analysis
      # @param files [Array<String>] List of file paths
      # @return [Hash] Directory statistics
      def analyze_directories(files)
        return {} if files.empty?

        directory_counts = {}

        files.each do |file|
          # Get all directory levels for analysis
          path_parts = file.split("/")

          # Process each directory level
          current_path = ""
          path_parts.each_with_index do |part, index|
            # Skip the last part (the filename)
            next if index == path_parts.size - 1

            # Build the path up to this level
            current_path = current_path.empty? ? part : "#{current_path}/#{part}"

            # Count occurrences
            directory_counts[current_path] ||= 0
            directory_counts[current_path] += 1
          end
        end

        # Sort directories by count to find hotspots
        sorted_dirs = directory_counts.sort_by { |_, count| -count }

        # Store top 10 directories with their counts for heatmap generation
        hotspot_dirs = sorted_dirs.first(10).to_h

        {
          directory_hotspots: hotspot_dirs,
          top_directory: sorted_dirs.first&.first || "",
          top_directory_count: sorted_dirs.first&.last || 0
        }
      end

      # Analyze file extensions for a list of files
      # @param files [Array<String>] List of file paths
      # @return [Hash] File extension statistics
      def analyze_extensions(files)
        return {} if files.empty?

        extension_counts = {}

        files.each do |file|
          # Extract file extension
          ext = File.extname(file).delete(".").downcase
          ext = "no_extension" if ext.empty?

          # Count occurrences
          extension_counts[ext] ||= 0
          extension_counts[ext] += 1
        end

        # Sort extensions by count
        sorted_exts = extension_counts.sort_by { |_, count| -count }

        # Store top 10 extensions with their counts
        hotspot_exts = sorted_exts.first(10).to_h

        {
          extension_hotspots: hotspot_exts,
          top_extension: sorted_exts.first&.first || "",
          top_extension_count: sorted_exts.first&.last || 0
        }
      end

      # Calculate code change volume from commits if available
      # @param event [Domain::Event] The GitHub event
      # @return [Hash] Code volume changes
      def extract_code_volume(event)
        total_additions = 0
        total_deletions = 0

        if event.data[:commits]
          event.data[:commits].each do |commit|
            # Some GitHub webhook payloads include stats
            if commit[:stats]
              total_additions += commit[:stats][:additions].to_i
              total_deletions += commit[:stats][:deletions].to_i
            end
          end
        end

        {
          code_additions: total_additions,
          code_deletions: total_deletions,
          code_churn: total_additions + total_deletions
        }
      end
    end
  end
end
