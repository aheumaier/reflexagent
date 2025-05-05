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
        dimensions = {
          operation: data[:operation] || parse_operation_from_event_name(event.name),
          repository: data[:repository] || "unknown",
          source: event.source
        }

        # Add environment info if available
        dimensions[:environment] = data[:environment] if data[:environment]

        # Add provider info if available
        dimensions[:provider] = data[:provider] || "github-actions"

        # Add status info if available
        dimensions[:status] = data[:status] if data[:status]

        # Handle specific operations
        case dimensions[:operation]
        when "build"
          # Add build-specific dimensions
          dimensions[:branch] = data[:branch] if data[:branch]
          dimensions[:commit_sha] = data[:commit_sha] if data[:commit_sha]
        when "deploy"
          # Add deployment-specific dimensions
          dimensions[:environment] ||= "production" # Default to production if not specified
        end

        dimensions
      end

      # Helper method to parse operation from event name
      # @param event_name [String] The event name (e.g., "ci.build.completed")
      # @return [String] The operation part of the event name
      def parse_operation_from_event_name(event_name)
        parts = event_name.split(".")
        return "unknown" if parts.size < 2

        parts[1] # Return the operation part (e.g., "build" from "ci.build.completed")
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
          # For non-conventional commits, attempt to infer the type
          inferred_type = infer_commit_type(
            message,
            added: commit[:added],
            modified: commit[:modified]
          )

          {
            commit_type: inferred_type,
            commit_description: message,
            commit_conventional: false,
            # If we were able to infer a type, mark it as inferred
            commit_type_inferred: inferred_type.present?
          }
        end
      end

      # Infer commit type from non-conventional commit messages
      # @param message [String] The commit message
      # @param added [Array<String>] Optional list of added files
      # @param modified [Array<String>] Optional list of modified files
      # @return [String, nil] The inferred commit type or nil if couldn't determine
      def infer_commit_type(message, added: nil, modified: nil)
        message = message.downcase.strip
        first_line = message.split("\n").first.to_s

        # Special cases for merge and WIP commits - check these first
        return "chore" if first_line.match?(/^\s*merge\s+/i) || first_line.match?(/^wip\b/i)

        # Common commit type patterns - order matters for precedence
        type_patterns = {
          "feat" => [
            /\badd(ed|ing|s)?\b/i,
            /\bnew\b/i,
            /\bimplement(ed|ing|s)?\b/i,
            /\bfeature\b/i,
            /\benhance(d|ment|s)?\b/i,
            /\bimprove(d|ment|s)?\b/i,
            /\bintroduce(d|s)?\b/i,
            /\bcreate(d|s)?\b/i
          ],
          "fix" => [
            /\bfix(ed|es|ing)?\b/i,
            /\bbug\b/i,
            /\bissue\b/i,
            /\bsolve(d|s)?\b/i,
            /\bresolve(d|s)?\b/i,
            /\bpatch(ed|ing|es)?\b/i,
            /\bcorrect(ed|s|ion)?\b/i,
            /\baddress(ed|es|ing)?\b/i,
            /\bhotfix\b/i
          ],
          "style" => [
            /\bstyle\b/i,
            /\bformat(ting|ted)?\b/i,
            /\bindent(ation)?\b/i,
            /\bwhitespace\b/i,
            /\bcsss?\b/i,
            /\blint(ing)?\b/i
          ],
          "docs" => [
            /\bdoc(s|umentation)?\b/i,
            /\bcomment(s|ed|ing)?\b/i,
            /\breadme\b/i,
            /\bupdate(d|s)? (docs|documentation|readme)\b/i
          ],
          "test" => [
            /\btest(s|ing|ed)?\b/i,
            /\bspec(s|ification)?\b/i,
            /\bcoverage\b/i,
            /\bunit tests?\b/i
          ],
          "perf" => [
            /\bperf(ormance)?\b/i,
            /\bspeed(s)? up\b/i,
            /\boptimiz(e|ation|ing)\b/i,
            /\bfaster\b/i,
            /\bimprove(d|s)? (speed|performance)\b/i
          ],
          "refactor" => [
            /\brefactor(ed|ing|s)?\b/i,
            /\bclean(ed|ing|s)?\b/i,
            /\bimprove(d|s)? (code|structure|implementation)\b/i,
            /\brestructure(d|s)?\b/i,
            /\bsimplif(y|ied|ies)\b/i,
            /\breorganize(d|s)?\b/i
          ],
          "chore" => [
            /\bchore\b/i,
            /\bmaintenance\b/i,
            /\bupdate(d|s)? dependencies\b/i,
            /\bdependenc(y|ies)\b/i,
            /\bversion bump\b/i,
            /\bupgrade(d|s)?\b/i,
            /\bconfig\b/i,
            /\bsetup\b/i
          ],
          "ci" => [
            /\bci\b/i,
            /\btravis\b/i,
            /\bjenkins\b/i,
            /\bgithub actions\b/i,
            /\bpipeline\b/i,
            /\bcontinuous integration\b/i,
            /\bworkflows?\b/i
          ],
          "build" => [
            /\bbuild\b/i,
            /\bcompil(e|ation)\b/i,
            /\bpackage\b/i,
            /\bbundl(e|ing)\b/i,
            /\bdeploy(ment)?\b/i
          ],
          "revert" => [
            /\brevert(ed|ing)?\b/i,
            /\bundo\b/i,
            /\broll(ing|ed)? back\b/i
          ]
        }

        # First, check for high-certainty patterns that indicate specific types
        # These need to be more specific than the general patterns
        # We check these in a specific order of precedence

        # Check for specific documentation patterns
        if first_line.match?(/^(update|add)(ed|ing|s)?\s+(the\s+)?(docs|documentation|readme|comments)/i) ||
           first_line.match?(/^comments?\b/i)
          return "docs"
        end

        # Check for specific performance patterns
        if first_line.match?(/^optimize\b/i) ||
           first_line.match?(/\bperformance\b/i) ||
           first_line.match?(/\bspeed up\b/i)
          return "perf"
        end

        # Check for specific style patterns
        if first_line.match?(/\bindentation\b/i) ||
           first_line.match?(/\bformatting\b/i) ||
           first_line.match?(/\bwhitespace\b/i)
          return "style"
        end

        # Check for specific test patterns
        if first_line.match?(/\bunit test/i) ||
           first_line.match?(/\btest(s| case| suite)/i) ||
           first_line.match?(/^add\b.+\btest/i) ||
           first_line.match?(/\bimprove\s+test\s+/i) ||
           first_line.match?(/\btest coverage\b/i)
          return "test"
        end

        # More specific matches for introducing features
        if first_line.match?(/\bintroduc(e|ing)\b.+/i) ||
           first_line.match?(/\bdark mode\b/i)
          return "feat"
        end

        # Then go through each type pattern to find general matches
        type_patterns.each do |type, patterns|
          patterns.each do |pattern|
            return type if first_line.match?(pattern)
          end
        end

        # Analyze file extensions if provided
        files = []
        files.concat(added) if added.is_a?(Array)
        files.concat(modified) if modified.is_a?(Array)

        # If we have files to analyze
        if files.any?
          extensions = files.map { |f| File.extname(f).downcase }.uniq

          # If only documentation files are changed
          return "docs" if extensions.all? { |ext| [".md", ".txt", ".doc", ".docx"].include?(ext) }

          # If only test files are changed
          return "test" if files.all? { |f| f.include?("/test/") || f.include?("/spec/") || f.match?(/_(test|spec)\./) }

          # If only CSS/SCSS files are changed
          return "style" if extensions.all? { |ext| [".css", ".scss", ".sass", ".less"].include?(ext) }
        end

        # Fallback: If the message is too ambiguous, return 'chore' as default
        return "chore" if first_line.length < 5

        # Attempt one more basic classification based on common verbs
        # These patterns are simpler but useful as a last resort
        case first_line
        when /\bfix(ed|es|ing)?\b/i then "fix"
        when /\badd(ed|ing|s)?\b/i then "feat"
        when /\bupdate(d|ing|s)?\b/i then "chore"
        when /\bremove(d|s)?\b/i then "refactor"
        when /\bmerge\b/i then "chore"
        when /\bclean(ed|s|ing)?\b/i then "refactor"
        else "chore" # Final fallback
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
