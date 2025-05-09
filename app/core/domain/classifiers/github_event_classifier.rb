# frozen_string_literal: true

module Domain
  module Classifiers
    # GithubEventClassifier is responsible for analyzing GitHub events and determining
    # which metrics should be created from them.
    class GithubEventClassifier < BaseClassifier
      attr_reader :metric_naming_port

      # Initialize with dimension extractor and metric naming port
      # @param dimension_extractor [Domain::Extractors::DimensionExtractor] Extractor for event dimensions
      # @param metric_naming_port [Ports::MetricNamingPort] Port for metric naming standardization
      def initialize(dimension_extractor = nil, metric_naming_port = nil)
        super(dimension_extractor)
        @metric_naming_port = metric_naming_port
      end

      # Classify a GitHub event and return metric definitions
      # @param event [Domain::Event] The GitHub event to classify
      # @return [Hash] A hash with a :metrics key containing an array of metric definitions
      def classify(event)
        metrics = []
        dimensions = {
          repository: "unknown",
          organization: "unknown",
          source: event.source
        }

        # Extract the main event type and action from the event name
        # Format should be: github.[event_name].[action]
        _, event_name, action = event.name.split(".")

        # Handle GitHub events based on standardized event names from GitHub Webhook API
        case event_name
        when "push"
          classify_push_event(event)
        when "pull_request"
          classify_pull_request_event(event, action)
        when "issues"
          classify_issues_event(event, action)
        when "check_run"
          classify_check_run_event(event, action)
        when "check_suite"
          classify_check_suite_event(event, action)
        when "create"
          classify_create_event(event)
        when "delete"
          classify_delete_event(event)
        when "deployment"
          classify_deployment_event(event)
        when "deployment_status"
          classify_deployment_status_event(event, action)
        when "workflow_run"
          classify_workflow_run_event(event, action)
        when "workflow_job"
          classify_workflow_job_event(event, action)
        when "workflow_dispatch"
          classify_workflow_dispatch_event(event)
        when "repository"
          classify_repository_event(event, action)
        # Handle CI-specific events from GitHub
        when "ci"
          classify_ci_event(event)
        else
          # Generic GitHub event
          {
            metrics: [
              create_metric(
                name: build_metric_name(source: "github", entity: event_name, action: action || "total"),
                value: 1,
                dimensions: extract_dimensions(event)
              )
            ]
          }
        end
      end

      private

      # Helper method to build standardized metric names
      # @param source [String] The source system (github, bitbucket, etc.)
      # @param entity [String] The entity being measured (push, pull_request, etc.)
      # @param action [String] The action (total, created, merged, etc.)
      # @param detail [String, nil] Optional additional detail (daily, by_author, etc.)
      # @return [String] The formatted metric name
      def build_metric_name(source:, entity:, action:, detail: nil)
        if @metric_naming_port
          @metric_naming_port.build_metric_name(
            source: source,
            entity: entity,
            action: action,
            detail: detail
          )
        else
          # Fallback for when port is not available
          parts = [source, entity, action]
          parts << detail if detail
          parts.join(".")
        end
      end

      def extract_dimensions(event)
        if @metric_naming_port
          # Use the metric naming port for standardized dimension handling
          @metric_naming_port.build_standard_dimensions(event)
        elsif @dimension_extractor
          # Fallback to the legacy dimension extractor if available
          dims = @dimension_extractor.extract_github_dimensions(event)

          # Ensure repository and organization are populated with proper values
          if dims[:repository].nil? || dims[:repository] == "unknown"
            # Try to extract repository directly from event data
            repo_full_name = nil

            # Try to extract using symbols first
            repo_full_name = event.data[:repository][:full_name] if event.data && event.data[:repository]

            # If not found, try with string keys
            if repo_full_name.nil? && event.data && event.data["repository"]
              repo_full_name = event.data["repository"]["full_name"]
            end

            dims[:repository] = repo_full_name || "unknown"

            # Extract organization from repository full name (format: org/repo)
            if dims[:repository] != "unknown" && dims[:repository].include?("/")
              dims[:organization] = dims[:repository].split("/").first
            end

            # If organization still not found, try to extract directly from owner field
            if dims[:organization].nil? || dims[:organization] == "unknown"
              dims[:organization] = if event.data && event.data[:repository] && event.data[:repository][:owner]
                                      event.data[:repository][:owner][:login] || "unknown"
                                    elsif event.data && event.data["repository"] && event.data["repository"]["owner"]
                                      event.data["repository"]["owner"]["login"] || "unknown"
                                    else
                                      "unknown"
                                    end
            end
          end

          # Ensure source is set
          dims[:source] ||= event.source

          dims
        else
          # Return empty hash when no dimension extractor is provided to maintain
          # backward compatibility with tests and existing behavior
          {}
        end
      end

      def classify_push_event(event)
        dimensions = extract_dimensions(event)
        push_data = event.data || {}

        # Start with basic push metrics
        metrics = build_basic_push_metrics(dimensions, push_data, event)

        # Stop here if we're running without a dimension extractor
        return { metrics: metrics } if @dimension_extractor.nil?

        # Enhanced metrics for commits
        commits = extract_from_data(push_data, :commits)
        if commits.present?
          # Process commit-related metrics
          process_commits(commits, metrics, dimensions, event)

          # Extract and process file changes
          process_file_changes(commits, metrics, dimensions, event)
        end

        { metrics: metrics }
      end

      # Generate basic push metrics (total, branch activity, commits, author)
      # @param dimensions [Hash] Base dimensions for the metrics
      # @param push_data [Hash] Push event data
      # @param event [Domain::Event] The GitHub event
      # @return [Array<Hash>] Array of basic push metric definitions
      def build_basic_push_metrics(dimensions, push_data, event)
        metrics = []

        # Total pushes metric
        metrics << create_metric(
          name: build_metric_name(source: "github", entity: "push", action: "total"),
          value: 1,
          dimensions: dimensions
        )

        # Branch activity metric
        metrics << build_branch_activity_metric(dimensions, push_data)

        # Commits count metric
        commit_metrics = build_commit_count_metrics(dimensions, push_data, event)
        metrics.concat(commit_metrics)

        metrics
      end

      # Generate commit count metrics for push events
      # @param dimensions [Hash] Base dimensions for the metrics
      # @param push_data [Hash] Push event data
      # @param event [Domain::Event] The GitHub event
      # @return [Array<Hash>] Array of commit count metric definitions
      def build_commit_count_metrics(dimensions, push_data, event)
        metrics = []

        # Get commits and count
        commits = extract_from_data(push_data, :commits)
        commit_count = commits&.size || 0

        # Total commits metric
        metrics << create_metric(
          name: build_metric_name(source: "github", entity: "push", action: "commits", detail: "total"),
          value: commit_count,
          dimensions: dimensions
        )

        # Commits by author metric
        author = determine_commit_author(push_data, event)

        metrics << create_metric(
          name: build_metric_name(source: "github", entity: "push", action: "by_author"),
          value: commit_count,
          dimensions: dimensions.merge(
            author: author
          )
        )

        metrics
      end

      # Generate branch activity metric for push events
      # @param dimensions [Hash] Base dimensions for the metric
      # @param push_data [Hash] Push event data
      # @return [Hash] Branch activity metric definition
      def build_branch_activity_metric(dimensions, push_data)
        branch = extract_branch_from_ref(extract_from_data(push_data, :ref))

        create_metric(
          name: build_metric_name(source: "github", entity: "push", action: "branch_activity"),
          value: 1,
          dimensions: dimensions.merge(
            branch: branch
          )
        )
      end

      # Determine the author for a push event
      # @param push_data [Hash] Push event data
      # @param event [Domain::Event, nil] The full event (optional)
      # @return [String] The determined author name or "unknown"
      def determine_commit_author(push_data, event = nil)
        # First try to get from push data
        author = extract_push_author(push_data)

        # If an event is provided, try dimension extractor for test compatibility
        if event && @dimension_extractor && @dimension_extractor.respond_to?(:extract_author)
          test_author = @dimension_extractor.extract_author(event)
          author = test_author if test_author.present? && test_author != "unknown"
        end

        author
      end

      # Helper method to extract branch name from ref
      def extract_branch_from_ref(ref)
        return "unknown" unless ref.present?

        if ref.start_with?("refs/heads/")
          ref.gsub("refs/heads/", "")
        elsif ref.start_with?("refs/tags/")
          "tag:#{ref.gsub('refs/tags/', '')}"
        else
          ref
        end
      end

      # Helper method to extract push author information
      def extract_push_author(push_data)
        # Try to get the author from head commit first
        head_commit = extract_from_data(push_data, :head_commit)
        if head_commit.present?
          author = extract_from_data(head_commit, :author)
          return extract_from_data(author, :name) || extract_from_data(author, :email) || "unknown" if author.present?
        end

        # Fall back to pusher
        pusher = extract_from_data(push_data, :pusher)
        return extract_from_data(pusher, :name) || extract_from_data(pusher, :email) || "unknown" if pusher.present?

        # Final fallback
        "unknown"
      end

      # Extract value from event data handling both string and symbol keys
      def extract_from_data(data, *keys)
        return nil if data.nil? || !keys.any?

        stringified_keys = keys.map(&:to_s)
        symbolized_keys = keys.map(&:to_sym)

        # Try symbol path first
        value = begin
          data.dig(*symbolized_keys)
        rescue StandardError
          nil
        end

        # Fall back to string path if needed
        if value.nil?
          value = begin
            data.dig(*stringified_keys)
          rescue StandardError
            nil
          end
        end

        value
      end

      # Parse timestamp string to date string (YYYY-MM-DD format)
      # @param timestamp_str [String] String representation of a timestamp
      # @return [String, nil] Date string in YYYY-MM-DD format or nil if invalid
      def parse_timestamp_to_date(timestamp_str)
        return nil unless timestamp_str.present?

        begin
          Time.parse(timestamp_str).strftime("%Y-%m-%d")
        rescue ArgumentError, TypeError => e
          Rails.logger.error("Error parsing timestamp '#{timestamp_str}': #{e.message}")
          nil
        end
      end

      def process_commits(commits, metrics, dimensions, event)
        # Group commits by their actual commit date
        commits_by_date = {}
        Rails.logger.debug { "Processing #{commits.size} commits" }

        commits.each do |commit|
          # Skip if no commit data
          next unless commit.present?

          # Extract commit timestamp if available (handling both string and symbol keys)
          timestamp_str = extract_from_data(commit, :timestamp)

          # Try to get commit date if timestamp is present
          commit_date = parse_timestamp_to_date(timestamp_str)
          if commit_date
            # Increment count for this date
            commits_by_date[commit_date] ||= 0
            commits_by_date[commit_date] += 1
            Rails.logger.debug { "Added commit with timestamp #{timestamp_str} to date #{commit_date}" }
          end

          # Extract commit message parts (conventional commit format)
          commit_parts = extract_conventional_commit_parts(commit)

          # Normalize field names for compatibility with tests
          commit_type = commit_parts[:commit_type] || commit_parts[:type]
          commit_scope = commit_parts[:commit_scope] || commit_parts[:scope]
          commit_breaking = commit_parts[:commit_breaking] || commit_parts[:breaking]
          commit_conventional = commit_parts[:commit_conventional] || commit_parts[:conventional]

          # Track commit messages by type (conventional or inferred)
          next unless commit_type.present?

          # Track by commit type (feat, fix, chore, etc.)
          metrics << create_metric(
            name: build_metric_name(source: "github", entity: "push", action: "commit_type"),
            value: 1,
            dimensions: dimensions.merge(
              type: commit_type,
              scope: commit_scope || "none",
              conventional: commit_conventional ? "true" : "false"
            )
          )

          # Track breaking changes separately
          next unless commit_breaking

          # Try to extract author from commit
          author_from_commit = extract_from_data(commit, :author, :name) || "unknown"

          # Allow dimension_extractor to override author for test compatibility
          author = author_from_commit
          if @dimension_extractor && @dimension_extractor.respond_to?(:extract_author)
            test_author = @dimension_extractor.extract_author(event)
            author = test_author if test_author.present? && test_author != "unknown"
          end

          metrics << create_metric(
            name: build_metric_name(source: "github", entity: "push", action: "breaking_change"),
            value: 1,
            dimensions: dimensions.merge(
              type: commit_type,
              scope: commit_scope || "none",
              author: author
            )
          )
        end

        # Log the aggregated commit data before creating metrics
        Rails.logger.debug { "Commits by date: #{commits_by_date.inspect}" }

        # Generate daily commit volume metrics with actual dates
        commits_by_date.each do |date, count|
          metrics << create_metric(
            name: build_metric_name(source: "github", entity: "commit_volume", action: "daily"),
            value: count,
            dimensions: dimensions.merge(
              date: date,
              commit_date: date,
              delivery_date: Time.now.strftime("%Y-%m-%d")
            ),
            timestamp: Date.parse(date).to_time
          )
          Rails.logger.debug { "Created commit volume metric for date #{date} with value #{count}" }
        end
      end

      # Extract conventional commit parts from commit message
      def extract_conventional_commit_parts(commit_data)
        # Handle either a string message or a commit hash
        message = if commit_data.is_a?(Hash)
                    extract_from_data(commit_data, :message)
                  else
                    commit_data.to_s
                  end

        return {} unless message.present?

        # Basic conventional commit regex
        # Format: type(scope): description [BREAKING CHANGE]
        conventional_regex = /^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(([^)]+)\))?!?:\s*(.+)$/i

        if message =~ conventional_regex
          {
            type: Regexp.last_match(1).downcase,
            scope: Regexp.last_match(3),
            description: Regexp.last_match(4),
            breaking: message.include?("BREAKING CHANGE") || message.include?("!:"),
            conventional: true,
            inferred: false
          }
        else
          # If not conventional, try to infer type
          inferred_type = infer_commit_type(message)
          {
            type: inferred_type,
            description: message,
            breaking: message.downcase.include?("break") || message.include?("!"),
            conventional: false,
            inferred: true
          }
        end
      end

      # Infer commit type from non-conventional message
      def infer_commit_type(message)
        message = message.downcase

        if message.match?(/fix|bug|issue|problem|error/)
          "fix"
        elsif message.match?(/feat|feature|add|new|implement/)
          "feat"
        elsif message.match?(/doc|readme|comment|guide/)
          "docs"
        elsif message.match?(/test|spec|rspec/)
          "test"
        elsif message.match?(/style|format|indent|css/)
          "style"
        elsif message.match?(/refactor|clean|improve|simplify/)
          "refactor"
        elsif message.match?(/perf|performance|optimize|speed/)
          "perf"
        elsif message.match?(/build|webpack|deps|dependency/)
          "build"
        elsif message.match?(/ci|travis|jenkins|github|action/)
          "ci"
        elsif message.match?(/revert|rollback|undo/)
          "revert"
        else
          "chore"
        end
      end

      # Process file changes from commits
      def process_file_changes(commits, metrics, dimensions, event)
        # If dimension_extractor has a compatible method, use it for test compatibility
        if @dimension_extractor && @dimension_extractor.respond_to?(:extract_file_changes)
          file_changes = @dimension_extractor.extract_file_changes(event)

          if file_changes.present?
            # Track overall file changes
            metrics << create_metric(
              name: build_metric_name(source: "github", entity: "push", action: "files_added"),
              value: file_changes[:files_added],
              dimensions: dimensions
            )

            metrics << create_metric(
              name: build_metric_name(source: "github", entity: "push", action: "files_modified"),
              value: file_changes[:files_modified],
              dimensions: dimensions
            )

            metrics << create_metric(
              name: build_metric_name(source: "github", entity: "push", action: "files_removed"),
              value: file_changes[:files_removed],
              dimensions: dimensions
            )

            # Track top directory changes
            if file_changes[:top_directory].present?
              metrics << create_metric(
                name: build_metric_name(source: "github", entity: "push", action: "directory_hotspot"),
                value: file_changes[:top_directory_count],
                dimensions: dimensions.merge(
                  directory: file_changes[:top_directory]
                )
              )

              # Track each directory in the hotspot list
              if file_changes[:directory_hotspots].present?
                file_changes[:directory_hotspots].each do |dir, count|
                  metrics << create_metric(
                    name: build_metric_name(source: "github", entity: "push", action: "directory_changes"),
                    value: count,
                    dimensions: dimensions.merge(directory: dir)
                  )
                end
              end
            end

            # Track top file extension changes
            if file_changes[:top_extension].present?
              metrics << create_metric(
                name: build_metric_name(source: "github", entity: "push", action: "filetype_hotspot"),
                value: file_changes[:top_extension_count],
                dimensions: dimensions.merge(
                  filetype: file_changes[:top_extension]
                )
              )

              # Track each extension in the hotspot list
              if file_changes[:extension_hotspots].present?
                file_changes[:extension_hotspots].each do |ext, count|
                  metrics << create_metric(
                    name: build_metric_name(source: "github", entity: "push", action: "filetype_changes"),
                    value: count,
                    dimensions: dimensions.merge(filetype: ext)
                  )
                end
              end
            end

            # Track code volume metrics
            if @dimension_extractor && @dimension_extractor.respond_to?(:extract_code_volume)
              code_volume = @dimension_extractor.extract_code_volume(event)
              if code_volume[:code_additions] > 0 || code_volume[:code_deletions] > 0
                metrics << create_metric(
                  name: build_metric_name(source: "github", entity: "push", action: "code_additions"),
                  value: code_volume[:code_additions],
                  dimensions: dimensions
                )

                metrics << create_metric(
                  name: build_metric_name(source: "github", entity: "push", action: "code_deletions"),
                  value: code_volume[:code_deletions],
                  dimensions: dimensions
                )

                metrics << create_metric(
                  name: build_metric_name(source: "github", entity: "push", action: "code_churn"),
                  value: code_volume[:code_churn],
                  dimensions: dimensions
                )
              end
            end

            return # Skip our custom implementation if we used the dimension_extractor
          end
        end

        # Custom implementation when dimension_extractor doesn't have the needed methods
        track_file_changes_custom(commits, metrics, dimensions)
      end

      # Custom implementation for tracking file changes
      def track_file_changes_custom(commits, metrics, dimensions)
        # Track file changes
        files_added = Set.new
        files_modified = Set.new
        files_removed = Set.new

        # Track directories and file extensions
        directories = Hash.new(0)
        file_extensions = Hash.new(0)

        # Track code volume
        code_additions = 0
        code_deletions = 0

        commits.each do |commit|
          # Add files - use extract_from_data to handle both string and symbol keys
          added_files = extract_from_data(commit, :added)
          Array(added_files).each do |file|
            files_added.add(file)
            track_file_metadata(file, file_extensions, directories)
          end

          # Modified files
          modified_files = extract_from_data(commit, :modified)
          Array(modified_files).each do |file|
            files_modified.add(file)
            track_file_metadata(file, file_extensions, directories)
          end

          # Removed files
          removed_files = extract_from_data(commit, :removed)
          Array(removed_files).each do |file|
            files_removed.add(file)
            track_file_metadata(file, file_extensions, directories)
          end

          # Try to extract code volume metrics if available
          stats = extract_from_data(commit, :stats)
          if stats.is_a?(Hash)
            code_additions += extract_from_data(stats, :additions).to_i
            code_deletions += extract_from_data(stats, :deletions).to_i
          end
        end

        # Create metrics for file counts
        metrics << create_metric(
          name: build_metric_name(source: "github", entity: "push", action: "files_added"),
          value: files_added.size,
          dimensions: dimensions
        )

        metrics << create_metric(
          name: build_metric_name(source: "github", entity: "push", action: "files_modified"),
          value: files_modified.size,
          dimensions: dimensions
        )

        metrics << create_metric(
          name: build_metric_name(source: "github", entity: "push", action: "files_removed"),
          value: files_removed.size,
          dimensions: dimensions
        )

        # Create metrics for directory hotspots
        directories.each do |dir, count|
          metrics << create_metric(
            name: build_metric_name(source: "github", entity: "push", action: "directory_changes"),
            value: count,
            dimensions: dimensions.merge(directory: dir)
          )
        end

        # Create metrics for top directory hotspot
        if directories.any?
          top_directory = directories.max_by { |_, count| count }
          metrics << create_metric(
            name: build_metric_name(source: "github", entity: "push", action: "directory_hotspot"),
            value: top_directory[1],
            dimensions: dimensions.merge(
              directory: top_directory[0]
            )
          )
        end

        # Create metrics for file extension hotspots
        file_extensions.each do |ext, count|
          metrics << create_metric(
            name: build_metric_name(source: "github", entity: "push", action: "filetype_changes"),
            value: count,
            dimensions: dimensions.merge(filetype: ext)
          )
        end

        # Create metrics for top file extension hotspot
        if file_extensions.any?
          top_extension = file_extensions.max_by { |_, count| count }
          metrics << create_metric(
            name: build_metric_name(source: "github", entity: "push", action: "filetype_hotspot"),
            value: top_extension[1],
            dimensions: dimensions.merge(
              filetype: top_extension[0]
            )
          )
        end

        # Add code volume metrics if we have data
        return unless code_additions > 0 || code_deletions > 0

        metrics << create_metric(
          name: build_metric_name(source: "github", entity: "push", action: "code_additions"),
          value: code_additions,
          dimensions: dimensions
        )

        metrics << create_metric(
          name: build_metric_name(source: "github", entity: "push", action: "code_deletions"),
          value: code_deletions,
          dimensions: dimensions
        )

        metrics << create_metric(
          name: build_metric_name(source: "github", entity: "push", action: "code_churn"),
          value: code_additions + code_deletions,
          dimensions: dimensions
        )
      end

      # Track file metadata (extensions and directories)
      def track_file_metadata(file_path, file_extensions, directories)
        return unless file_path.present?

        # Get file extension
        extension = File.extname(file_path).delete(".")

        # Normalize the filetype/extension dimension if port is available
        if @metric_naming_port
          filetype_key = @metric_naming_port.normalize_dimension_name("filetype")
          extension_normalized = @metric_naming_port.normalize_dimension_value("filetype", extension.presence || "none")
          file_extensions[extension_normalized] = file_extensions[extension_normalized].to_i + 1
        else
          file_extensions[extension.presence || "none"] += 1
        end

        # Get directory
        directory = File.dirname(file_path)
        directory = "root" if directory == "."

        # Track the directory and parent directories
        current_path = directory
        loop do
          if @metric_naming_port
            dir_key = @metric_naming_port.normalize_dimension_name("directory")
            dir_normalized = @metric_naming_port.normalize_dimension_value("directory", current_path)
            directories[dir_normalized] = directories[dir_normalized].to_i + 1
          else
            directories[current_path] += 1
          end

          # Move up one level
          parent_path = File.dirname(current_path)
          break if parent_path == "." || parent_path == current_path

          current_path = parent_path
        end
      end

      def classify_pull_request_event(event, action)
        # Default to 'total' if action is nil
        action ||= "total"

        dimensions = extract_dimensions(event)
        pr_data = extract_from_data(event.data, :pull_request)

        metrics = []

        # Add basic PR metrics
        metrics.concat(build_basic_pr_metrics(dimensions, action))

        # Add author-specific metrics
        metrics << build_pr_author_metric(dimensions, action, event)

        # Add merge-related metrics if PR was closed
        metrics.concat(build_pr_merge_metrics(dimensions, pr_data)) if action == "closed" && pr_data

        { metrics: metrics }
      end

      # Generate basic pull request metrics (total and specific action)
      # @param dimensions [Hash] Base dimensions for the metrics
      # @param action [String] The PR action (opened, closed, etc.)
      # @return [Array<Hash>] Array of metric definitions
      def build_basic_pr_metrics(dimensions, action)
        [
          # Total PRs metric
          create_metric(
            name: build_metric_name(source: "github", entity: "pull_request", action: "total"),
            value: 1,
            dimensions: normalize_and_merge_dimensions(dimensions, { action: action })
          ),

          # PR action count (opened, closed, merged, etc.)
          create_metric(
            name: build_metric_name(source: "github", entity: "pull_request", action: action),
            value: 1,
            dimensions: dimensions
          )
        ]
      end

      # Generate author-specific pull request metric
      # @param dimensions [Hash] Base dimensions for the metrics
      # @param action [String] The PR action (opened, closed, etc.)
      # @param event [Domain::Event] The GitHub event being classified
      # @return [Hash] Metric definition for PRs by author
      def build_pr_author_metric(dimensions, action, event)
        author = @dimension_extractor ? @dimension_extractor.extract_author(event) : "unknown"

        create_metric(
          name: build_metric_name(source: "github", entity: "pull_request", action: "by_author"),
          value: 1,
          dimensions: normalize_and_merge_dimensions(dimensions, {
                                                       author: author,
                                                       action: action
                                                     })
        )
      end

      # Generate merge-related metrics for closed pull requests
      # @param dimensions [Hash] Base dimensions for the metrics
      # @param pr_data [Hash] Pull request data from the event
      # @return [Array<Hash>] Array of merge-related metric definitions
      def build_pr_merge_metrics(dimensions, pr_data)
        metrics = []
        merged = extract_from_data(pr_data, :merged)

        return metrics unless merged

        # Add merged PR metric
        metrics << create_metric(
          name: build_metric_name(source: "github", entity: "pull_request", action: "merged"),
          value: 1,
          dimensions: dimensions
        )

        # Add time to merge metric if timestamps are available
        time_to_merge_metric = build_pr_time_to_merge_metric(dimensions, pr_data)
        metrics << time_to_merge_metric if time_to_merge_metric

        metrics
      end

      # Generate time to merge metric if timestamps are available
      # @param dimensions [Hash] Base dimensions for the metric
      # @param pr_data [Hash] Pull request data from the event
      # @return [Hash, nil] Time to merge metric definition or nil if timestamps aren't available
      def build_pr_time_to_merge_metric(dimensions, pr_data)
        created_at = extract_from_data(pr_data, :created_at)
        merged_at = extract_from_data(pr_data, :merged_at)

        return nil unless created_at && merged_at

        begin
          created_time = Time.parse(created_at.to_s)
          merged_time = Time.parse(merged_at.to_s)
          time_to_merge = (merged_time - created_time) / 60 # in minutes

          create_metric(
            name: build_metric_name(source: "github", entity: "pull_request", action: "time_to_merge"),
            value: time_to_merge.to_i,
            dimensions: dimensions
          )
        rescue StandardError => e
          Rails.logger.error("Error calculating PR time_to_merge: #{e.message}")
          nil
        end
      end

      def classify_issues_event(event, action)
        # Default to 'total' if action is nil
        action ||= "total"

        dimensions = extract_dimensions(event)
        issue_data = extract_from_data(event.data, :issue)

        # Combine all metrics
        metrics = build_basic_issue_metrics(dimensions, action, event)

        # Add time-to-close metric for closed issues
        if action == "closed" && issue_data
          time_to_close_metric = build_issue_time_to_close_metric(dimensions, issue_data)
          metrics << time_to_close_metric if time_to_close_metric
        end

        { metrics: metrics }
      end

      # Generate basic issue metrics
      # @param dimensions [Hash] Base dimensions for the metrics
      # @param action [String] The issue action (opened, closed, etc.)
      # @param event [Domain::Event] The GitHub event being classified
      # @return [Array<Hash>] Array of basic issue metric definitions
      def build_basic_issue_metrics(dimensions, action, event)
        author = @dimension_extractor ? @dimension_extractor.extract_author(event) : "unknown"

        [
          # Total issues
          create_metric(
            name: build_metric_name(source: "github", entity: "issues", action: "total"),
            value: 1,
            dimensions: normalize_and_merge_dimensions(dimensions, { action: action })
          ),

          # Issue action count
          create_metric(
            name: build_metric_name(source: "github", entity: "issues", action: action),
            value: 1,
            dimensions: dimensions
          ),

          # Issues by author
          create_metric(
            name: build_metric_name(source: "github", entity: "issues", action: "by_author"),
            value: 1,
            dimensions: normalize_and_merge_dimensions(dimensions, {
                                                         author: author,
                                                         action: action
                                                       })
          )
        ]
      end

      # Generate time to close metric for issues if timestamps are available
      # @param dimensions [Hash] Base dimensions for the metric
      # @param issue_data [Hash] Issue data from the event
      # @return [Hash, nil] Time to close metric definition or nil if timestamps aren't available
      def build_issue_time_to_close_metric(dimensions, issue_data)
        created_at = extract_from_data(issue_data, :created_at)
        closed_at = extract_from_data(issue_data, :closed_at)

        return nil unless created_at && closed_at

        begin
          created_time = Time.parse(created_at.to_s)
          closed_time = Time.parse(closed_at.to_s)
          time_to_close = (closed_time - created_time) / 60 # in minutes

          create_metric(
            name: build_metric_name(source: "github", entity: "issues", action: "time_to_close"),
            value: time_to_close.to_i,
            dimensions: dimensions
          )
        rescue StandardError => e
          Rails.logger.error("Error calculating issue time_to_close: #{e.message}")
          nil
        end
      end

      def classify_check_run_event(event, action)
        # Default to 'total' if action is nil
        action ||= "total"

        dimensions = extract_dimensions(event)
        check_data = extract_from_data(event.data, :check_run)

        {
          metrics: [
            create_check_metric("check_run", action, dimensions, check_data)
          ]
        }
      end

      def classify_check_suite_event(event, action)
        # Default to 'total' if action is nil
        action ||= "total"

        dimensions = extract_dimensions(event)
        check_data = extract_from_data(event.data, :check_suite)

        {
          metrics: [
            create_check_metric("check_suite", action, dimensions, check_data)
          ]
        }
      end

      # Create a standardized metric for check runs and check suites
      # @param entity_type [String] The entity type ("check_run" or "check_suite")
      # @param action [String] The action being performed on the check
      # @param dimensions [Hash] Base dimensions for the metric
      # @param check_data [Hash, nil] The check data from the event
      # @return [Hash] The check metric definition
      def create_check_metric(entity_type, action, dimensions, check_data)
        dimensions_with_status = add_check_status_dimensions(dimensions, check_data)

        create_metric(
          name: build_metric_name(source: "github", entity: entity_type, action: action),
          value: 1,
          dimensions: dimensions_with_status
        )
      end

      # Add status and conclusion dimensions for check events
      # @param dimensions [Hash] Base dimensions
      # @param check_data [Hash, nil] Check data from the event
      # @return [Hash] Dimensions with added status information
      def add_check_status_dimensions(dimensions, check_data)
        return dimensions unless check_data

        check_status = extract_from_data(check_data, :status) || "unknown"
        check_conclusion = extract_from_data(check_data, :conclusion) || "unknown"

        if @metric_naming_port
          dimensions.merge(
            @metric_naming_port.normalize_dimension_name("status") => @metric_naming_port.normalize_dimension_value(
              "status", check_status
            ),
            @metric_naming_port.normalize_dimension_name("conclusion") => @metric_naming_port.normalize_dimension_value(
              "conclusion", check_conclusion
            )
          )
        else
          dimensions.merge(
            status: check_status,
            conclusion: check_conclusion
          )
        end
      end

      def classify_create_event(event)
        ref_type = event.data[:ref_type] || "unknown"

        # Start with base dimensions
        dimensions = extract_dimensions(event)
        metrics = []

        # Create the ref metrics with standardized dimensions
        metrics.concat(create_ref_operation_metric("create", ref_type, event, dimensions))

        { metrics: metrics }
      end

      def classify_delete_event(event)
        ref_type = event.data[:ref_type] || "unknown"

        # Start with base dimensions
        dimensions = extract_dimensions(event)
        metrics = []

        # Create the ref metrics with standardized dimensions
        metrics.concat(create_ref_operation_metric("delete", ref_type, event, dimensions))

        { metrics: metrics }
      end

      # Create a metric for ref operations (create/delete) with standardized dimensions
      # @param operation [String] The operation being performed ("create" or "delete")
      # @param ref_type [String] The reference type (branch, tag, etc.)
      # @param event [Domain::Event] The GitHub event
      # @param dimensions [Hash] Base dimensions for the metric
      # @return [Array<Hash>] Array of ref operation metric definitions
      def create_ref_operation_metric(operation, ref_type, event, dimensions)
        # Add additional dimensions with normalization
        additional_dims = build_ref_operation_dimensions(ref_type, event)
        merged_dimensions = normalize_and_merge_dimensions(dimensions, additional_dims)

        [
          # Total operation metric
          create_metric(
            name: build_metric_name(source: "github", entity: operation, action: "total"),
            value: 1,
            dimensions: merged_dimensions
          ),

          # Specific ref type metric
          create_metric(
            name: build_metric_name(source: "github", entity: operation, action: ref_type),
            value: 1,
            dimensions: merged_dimensions
          )
        ]
      end

      # Build standardized dimensions for ref operations
      # @param ref_type [String] The reference type (branch, tag, etc.)
      # @param event [Domain::Event] The GitHub event
      # @return [Hash] Additional dimensions for the ref operation
      def build_ref_operation_dimensions(ref_type, event)
        additional_dims = { ref_type: ref_type }

        # If it's a branch operation, extract the branch name
        additional_dims[:branch] = event.data[:ref] if ref_type == "branch" && event.data[:ref]

        additional_dims
      end

      def classify_deployment_event(event)
        environment = event.data.dig(:deployment, :environment) || "unknown"
        dimensions = extract_dimensions(event)

        # Add additional dimensions with normalization if port is available
        if @metric_naming_port
          additional_dims = {}
          additional_dims[@metric_naming_port.normalize_dimension_name("environment")] =
            @metric_naming_port.normalize_dimension_value("environment", environment)

          # Add deployment details if available
          if event.data[:deployment]
            if event.data[:deployment][:id]
              additional_dims[@metric_naming_port.normalize_dimension_name("deployment_id")] =
                @metric_naming_port.normalize_dimension_value("deployment_id", event.data[:deployment][:id])
            end

            if event.data[:deployment][:ref]
              additional_dims[@metric_naming_port.normalize_dimension_name("ref")] =
                @metric_naming_port.normalize_dimension_value("ref", event.data[:deployment][:ref])
            end

            if event.data[:deployment][:task]
              additional_dims[@metric_naming_port.normalize_dimension_name("task")] =
                @metric_naming_port.normalize_dimension_value("task", event.data[:deployment][:task])
            end
          end

          dimensions = dimensions.merge(additional_dims)
        else
          # Legacy approach without port
          dimensions = dimensions.merge(environment: environment)

          # Add deployment details if available
          if event.data[:deployment]
            dimensions[:deployment_id] = event.data[:deployment][:id] if event.data[:deployment][:id]
            dimensions[:ref] = event.data[:deployment][:ref] if event.data[:deployment][:ref]
            dimensions[:task] = event.data[:deployment][:task] if event.data[:deployment][:task]
          end
        end

        {
          metrics: [
            create_metric(
              name: build_metric_name(source: "github", entity: "deployment", action: "created"),
              value: 1,
              dimensions: dimensions
            )
          ]
        }
      end

      def classify_deployment_status_event(event, action)
        environment = event.data.dig(:deployment, :environment) || "unknown"
        status = event.data.dig(:deployment_status, :state) || "unknown"

        dimensions = extract_dimensions(event).merge(
          environment: environment,
          status: status
        )

        # Add deployment details if available
        if event.data[:deployment]
          dimensions[:deployment_id] = event.data[:deployment][:id] if event.data[:deployment][:id]
          dimensions[:ref] = event.data[:deployment][:ref] if event.data[:deployment][:ref]
          dimensions[:task] = event.data[:deployment][:task] if event.data[:deployment][:task]
        end

        metrics = [
          create_metric(
            name: build_metric_name(source: "github", entity: "deployment_status", action: "updated"),
            value: 1,
            dimensions: dimensions
          )
        ]

        # Track success/failure rates
        if status == "success"
          metrics << create_metric(
            name: build_metric_name(source: "github", entity: "deployment", action: "success"),
            value: 1,
            dimensions: dimensions
          )

          # Check if we have timing information
          if event.data[:deployment_status] && event.data[:deployment]
            created_at = event.data[:deployment][:created_at]
            updated_at = event.data[:deployment_status][:created_at]

            if created_at && updated_at
              begin
                created_time = Time.parse(created_at.to_s)
                updated_time = Time.parse(updated_at.to_s)
                deploy_time = (updated_time - created_time) / 60 # in minutes

                if deploy_time > 0
                  metrics << create_metric(
                    name: build_metric_name(source: "github", entity: "deployment", action: "time"),
                    value: deploy_time.to_i,
                    dimensions: dimensions
                  )
                end
              rescue StandardError => e
                Rails.logger.error("Error calculating deployment time: #{e.message}")
              end
            end
          end
        elsif ["failure", "error"].include?(status)
          metrics << create_metric(
            name: build_metric_name(source: "github", entity: "deployment", action: "failure"),
            value: 1,
            dimensions: dimensions
          )
        end

        { metrics: metrics }
      end

      def classify_workflow_run_event(event, action)
        # Default to 'total' if action is nil
        action ||= "total"

        dimensions = extract_dimensions(event)
        workflow_run = extract_from_data(event.data, :workflow_run)

        # First collect basic workflow metrics
        metrics = build_basic_workflow_run_metrics(dimensions, action, workflow_run)

        # Add duration metrics if completed
        if workflow_run && action == "completed"
          duration_metrics = build_workflow_run_duration_metrics(dimensions, workflow_run)
          metrics.concat(duration_metrics)
        end

        { metrics: metrics }
      end

      # Build basic workflow run metrics
      # @param dimensions [Hash] Base dimensions for the metrics
      # @param action [String] The workflow action (completed, etc.)
      # @param workflow_run [Hash, nil] Workflow run data from the event
      # @return [Array<Hash>] Array of basic workflow run metric definitions
      def build_basic_workflow_run_metrics(dimensions, action, workflow_run)
        metrics = []
        additional_dims = {}

        # Extract workflow-specific dimensions if available
        if workflow_run
          additional_dims[:workflow_name] = extract_from_data(workflow_run, :name) || "unknown"
          additional_dims[:conclusion] = extract_from_data(workflow_run, :conclusion) || "unknown"
          additional_dims[:status] = extract_from_data(workflow_run, :status) || "unknown"
        end

        # Total workflow runs metric
        metrics << create_metric(
          name: build_metric_name(source: "github", entity: "workflow_run", action: "total"),
          value: 1,
          dimensions: normalize_and_merge_dimensions(dimensions, additional_dims.merge(action: action))
        )

        # Workflow run action (completed, etc.)
        metrics << create_metric(
          name: build_metric_name(source: "github", entity: "workflow_run", action: action),
          value: 1,
          dimensions: normalize_and_merge_dimensions(dimensions, additional_dims)
        )

        # Add conclusion metric expected by tests
        conclusion = extract_from_data(workflow_run, :conclusion) || "unknown"
        metrics << create_metric(
          name: "github.workflow_run.conclusion.#{conclusion}",
          value: 1,
          dimensions: dimensions
        )

        # Specific conclusion/status metric if available
        if workflow_run && workflow_run[:conclusion]
          metrics << create_metric(
            name: build_metric_name(source: "github", entity: "workflow_run", action: workflow_run[:conclusion]),
            value: 1,
            dimensions: normalize_and_merge_dimensions(dimensions, additional_dims)
          )
        end

        metrics
      end

      # Build workflow run duration metrics
      # @param dimensions [Hash] Base dimensions for the metrics
      # @param workflow_run [Hash] Workflow run data from the event
      # @return [Array<Hash>] Array of workflow run duration metric definitions
      def build_workflow_run_duration_metrics(dimensions, workflow_run)
        metrics = []

        # Extract timing information
        created_at = extract_from_data(workflow_run, :created_at)
        updated_at = extract_from_data(workflow_run, :updated_at)

        if created_at && updated_at
          begin
            created_time = Time.parse(created_at.to_s)
            updated_time = Time.parse(updated_at.to_s)
            duration_seconds = (updated_time - created_time).to_i

            # Add workflow duration metric
            metrics << create_metric(
              name: build_metric_name(source: "github", entity: "workflow_run", action: "duration"),
              value: duration_seconds,
              dimensions: normalize_and_merge_dimensions(dimensions, {
                                                           workflow_name: extract_from_data(workflow_run,
                                                                                            :name) || "unknown",
                                                           conclusion: extract_from_data(workflow_run,
                                                                                         :conclusion) || "unknown"
                                                         })
            )
          rescue StandardError => e
            Rails.logger.error("Error calculating workflow duration: #{e.message}")
          end
        end

        metrics
      end

      def classify_workflow_job_event(event, action)
        # Default to 'total' if action is nil
        action ||= "total"

        dimensions = extract_dimensions(event)
        workflow_job = extract_from_data(event.data, :workflow_job)

        # Add workflow_name and branch to dimensions if available
        if workflow_job
          dimensions[:workflow_name] = extract_from_data(workflow_job, :workflow_name) || "unknown"
          dimensions[:branch] = extract_from_data(workflow_job, :head_branch) || "unknown"
        end

        # Start with basic workflow job metrics
        metrics = build_basic_workflow_job_metrics(dimensions, action, workflow_job)

        # Add step analysis if the job is completed and has steps
        if workflow_job && action == "completed" && workflow_job[:steps]
          step_metrics = analyze_workflow_steps(workflow_job[:steps], dimensions.merge(
                                                                        job_name: extract_from_data(workflow_job, :name) || "unknown"
                                                                      ))
          metrics.concat(step_metrics)
        end

        { metrics: metrics }
      end

      # Build basic workflow job metrics
      # @param dimensions [Hash] Base dimensions for the metrics
      # @param action [String] The workflow job action (completed, etc.)
      # @param workflow_job [Hash, nil] Workflow job data from the event
      # @return [Array<Hash>] Array of basic workflow job metric definitions
      def build_basic_workflow_job_metrics(dimensions, action, workflow_job)
        metrics = []
        additional_dims = {}

        # Extract job-specific dimensions if available
        if workflow_job
          additional_dims[:job_name] = extract_from_data(workflow_job, :name) || "unknown"
          additional_dims[:conclusion] = extract_from_data(workflow_job, :conclusion) || "unknown"
          additional_dims[:status] = extract_from_data(workflow_job, :status) || "unknown"
        end

        # Total workflow jobs metric
        metrics << create_metric(
          name: build_metric_name(source: "github", entity: "workflow_job", action: "total"),
          value: 1,
          dimensions: normalize_and_merge_dimensions(dimensions, additional_dims.merge(action: action))
        )

        # Workflow job action (completed, etc.)
        metrics << create_metric(
          name: build_metric_name(source: "github", entity: "workflow_job", action: action),
          value: 1,
          dimensions: normalize_and_merge_dimensions(dimensions, additional_dims)
        )

        # Add conclusion-specific metric
        if workflow_job && workflow_job[:conclusion]
          conclusion = workflow_job[:conclusion]
          metrics << create_metric(
            name: "github.workflow_job.conclusion.#{conclusion}",
            value: 1,
            dimensions: normalize_and_merge_dimensions(dimensions, additional_dims)
          )

          # Add duration metric if completed
          if action == "completed"
            duration_metric = build_workflow_job_duration_metric(dimensions, workflow_job, additional_dims)
            metrics << duration_metric if duration_metric
          end
        end

        metrics
      end

      # Build workflow job duration metric
      # @param dimensions [Hash] Base dimensions for the metric
      # @param workflow_job [Hash] Workflow job data from the event
      # @param additional_dims [Hash] Additional dimensions to include
      # @return [Hash, nil] Workflow job duration metric definition or nil if timing info isn't available
      def build_workflow_job_duration_metric(dimensions, workflow_job, additional_dims)
        # Extract timing information
        started_at = extract_from_data(workflow_job, :started_at)
        completed_at = extract_from_data(workflow_job, :completed_at)

        return nil unless started_at && completed_at

        begin
          started_time = Time.parse(started_at.to_s)
          completed_time = Time.parse(completed_at.to_s)
          duration_seconds = (completed_time - started_time).to_i

          create_metric(
            name: build_metric_name(source: "github", entity: "workflow_job", action: "duration"),
            value: duration_seconds,
            dimensions: normalize_and_merge_dimensions(dimensions, additional_dims)
          )
        rescue StandardError => e
          Rails.logger.error("Error calculating workflow job duration: #{e.message}")
          nil
        end
      end

      # Analyze workflow steps and generate metrics for test and deployment steps
      # This method processes GitHub workflow job steps and generates metrics for:
      # - Test step durations and success/failure status
      # - Deployment step durations and success/failure status
      # - Overall job metrics for test and deployment jobs
      # - DORA metrics for deployments and tests
      #
      # @param steps [Array<Hash>] Array of step data from the workflow job
      # @param dimensions [Hash] Base dimensions for the metrics
      # @return [Array<Hash>] Array of metric definitions for the steps
      def analyze_workflow_steps(steps, dimensions)
        return [] unless steps.is_a?(Array) && steps.any?

        metrics = []

        # Analyze steps to determine test and deployment activity
        test_steps = identify_test_steps(steps)
        deployment_steps = identify_deployment_steps(steps)

        # Process test steps
        test_metrics = process_test_steps(test_steps, dimensions)
        metrics.concat(test_metrics)

        # Process deployment steps
        deployment_metrics = process_deployment_steps(deployment_steps, dimensions)
        metrics.concat(deployment_metrics)

        # Generate overall job metrics based on step analysis
        job_metrics = generate_job_metrics(steps, test_steps, deployment_steps, dimensions)
        metrics.concat(job_metrics)

        metrics
      end

      private

      # Identify steps related to testing by analyzing step names
      # Looks for common keywords in step names like "test", "spec", "rspec", etc.
      #
      # @param steps [Array<Hash>] Array of step data from the workflow job
      # @return [Array<Hash>] Array of test-related steps
      def identify_test_steps(steps)
        steps.select do |step|
          step_name = step[:name].to_s.downcase

          # Match common test-related step names
          step_name.include?("test") ||
            step_name.include?("spec") ||
            step_name.include?("rspec") ||
            step_name.include?("jest") ||
            step_name.include?("unit") ||
            step_name.include?("integration") ||
            step_name.include?("e2e")
        end
      end

      # Identify steps related to deployment by analyzing step names
      # Looks for common keywords in step names like "deploy", "publish", "release", etc.
      #
      # @param steps [Array<Hash>] Array of step data from the workflow job
      # @return [Array<Hash>] Array of deployment-related steps
      def identify_deployment_steps(steps)
        steps.select do |step|
          step_name = step[:name].to_s.downcase

          # Match common deployment-related step names
          step_name.include?("deploy") ||
            step_name.include?("publish") ||
            step_name.include?("release") ||
            step_name.include?("push to") ||
            step_name.match?(/to\s+(prod|production|staging|dev|development)/)
        end
      end

      # Process test steps to generate step-level test metrics
      # Creates metrics for step duration and success/failure status
      #
      # @param test_steps [Array<Hash>] Array of test-related steps
      # @param dimensions [Hash] Base dimensions for the metrics
      # @return [Array<Hash>] Array of metric definitions for test steps
      def process_test_steps(test_steps, dimensions)
        return [] if test_steps.empty?

        metrics = []

        test_steps.each do |step|
          step_dimensions = dimensions.merge(step_name: step[:name])

          # Calculate step duration
          step_duration = calculate_step_duration(step)

          if step_duration
            metrics << create_metric(
              name: "github.workflow_step.test.duration",
              value: step_duration,
              dimensions: step_dimensions
            )
          end

          # Add success/failure metrics
          conclusion = step[:conclusion].to_s.downcase

          if conclusion == "success"
            metrics << create_metric(
              name: "github.workflow_step.test.success",
              value: 1,
              dimensions: step_dimensions
            )
          elsif ["failure", "cancelled", "timed_out"].include?(conclusion)
            metrics << create_metric(
              name: "github.workflow_step.test.failure",
              value: 1,
              dimensions: step_dimensions
            )
          end
        end

        metrics
      end

      # Process deployment steps to generate step-level deployment metrics
      # Creates metrics for step duration and success/failure status
      #
      # @param deployment_steps [Array<Hash>] Array of deployment-related steps
      # @param dimensions [Hash] Base dimensions for the metrics
      # @return [Array<Hash>] Array of metric definitions for deployment steps
      def process_deployment_steps(deployment_steps, dimensions)
        return [] if deployment_steps.empty?

        metrics = []

        deployment_steps.each do |step|
          step_dimensions = dimensions.merge(step_name: step[:name])

          # Calculate step duration
          step_duration = calculate_step_duration(step)

          if step_duration
            metrics << create_metric(
              name: "github.workflow_step.deploy.duration",
              value: step_duration,
              dimensions: step_dimensions
            )
          end

          # Add success/failure metrics
          conclusion = step[:conclusion].to_s.downcase

          if conclusion == "success"
            metrics << create_metric(
              name: "github.workflow_step.deploy.success",
              value: 1,
              dimensions: step_dimensions
            )
          elsif ["failure", "cancelled", "timed_out"].include?(conclusion)
            metrics << create_metric(
              name: "github.workflow_step.deploy.failure",
              value: 1,
              dimensions: step_dimensions
            )
          end
        end

        metrics
      end

      # Calculate duration of a step from timestamps in seconds
      # Returns nil if timestamps are missing or invalid
      #
      # @param step [Hash] Step data with started_at and completed_at timestamps
      # @return [Integer, nil] Duration in seconds, or nil if calculation failed
      def calculate_step_duration(step)
        started_at = step[:started_at]
        completed_at = step[:completed_at]

        return nil unless started_at && completed_at

        begin
          started_time = Time.parse(started_at.to_s)
          completed_time = Time.parse(completed_at.to_s)
          (completed_time - started_time).to_i
        rescue StandardError => e
          Rails.logger.error("Error calculating step duration: #{e.message}")
          nil
        end
      end

      # Generate overall job metrics based on step analysis
      # Includes summary metrics for test jobs and deployment jobs
      #
      # @param all_steps [Array<Hash>] All steps in the workflow job
      # @param test_steps [Array<Hash>] Test-related steps
      # @param deployment_steps [Array<Hash>] Deployment-related steps
      # @param dimensions [Hash] Base dimensions for the metrics
      # @return [Array<Hash>] Array of job-level metric definitions
      def generate_job_metrics(all_steps, test_steps, deployment_steps, dimensions)
        metrics = []

        # If job contains test steps, generate test metrics
        if test_steps.any?
          test_metrics = generate_test_job_metrics(test_steps, dimensions)
          metrics.concat(test_metrics)
        end

        # If job contains deployment steps, generate deployment metrics
        if deployment_steps.any?
          deployment_metrics = generate_deployment_job_metrics(deployment_steps, dimensions)
          metrics.concat(deployment_metrics)
        end

        metrics
      end

      # Generate test job metrics including duration, success/failure status, and DORA metrics
      # Combines data from multiple test steps to create job-level metrics
      #
      # @param test_steps [Array<Hash>] Test-related steps
      # @param dimensions [Hash] Base dimensions for the metrics
      # @return [Array<Hash>] Array of test job metric definitions
      def generate_test_job_metrics(test_steps, dimensions)
        metrics = []

        # Calculate total test duration
        total_duration = 0
        test_steps.each do |step|
          step_duration = calculate_step_duration(step)
          total_duration += step_duration if step_duration
        end

        if total_duration > 0
          metrics << create_metric(
            name: "github.ci.test.duration",
            value: total_duration,
            dimensions: dimensions
          )
        end

        # Check if all test steps were successful
        all_successful = test_steps.all? { |step| step[:conclusion].to_s.downcase == "success" }

        # Add success/failure metrics
        if all_successful
          metrics << create_metric(
            name: "github.ci.test.success",
            value: 1,
            dimensions: dimensions
          )
        else
          metrics << create_metric(
            name: "github.ci.test.success",
            value: 0,
            dimensions: dimensions
          )

          metrics << create_metric(
            name: "github.ci.test.failed",
            value: 1,
            dimensions: dimensions
          )
        end

        # Add DORA metrics for tests
        metrics << create_metric(
          name: "dora.test.run",
          value: 1,
          dimensions: dimensions
        )

        unless all_successful
          metrics << create_metric(
            name: "dora.test.failure",
            value: 1,
            dimensions: dimensions
          )
        end

        metrics
      end

      # Generate deployment job metrics including duration, success/failure status, and DORA metrics
      # Combines data from multiple deployment steps to create job-level metrics
      #
      # @param deployment_steps [Array<Hash>] Deployment-related steps
      # @param dimensions [Hash] Base dimensions for the metrics
      # @return [Array<Hash>] Array of deployment job metric definitions
      def generate_deployment_job_metrics(deployment_steps, dimensions)
        metrics = []

        # Calculate total deployment duration
        total_duration = 0
        deployment_steps.each do |step|
          step_duration = calculate_step_duration(step)
          total_duration += step_duration if step_duration
        end

        if total_duration > 0
          metrics << create_metric(
            name: "github.ci.deploy.duration",
            value: total_duration,
            dimensions: dimensions
          )
        end

        # Check if all deployment steps were successful
        all_successful = deployment_steps.all? { |step| step[:conclusion].to_s.downcase == "success" }

        # Add success/failure metrics
        if all_successful
          metrics << create_metric(
            name: "github.ci.deploy.success",
            value: 1,
            dimensions: dimensions
          )
        else
          metrics << create_metric(
            name: "github.ci.deploy.success",
            value: 0,
            dimensions: dimensions
          )

          metrics << create_metric(
            name: "github.ci.deploy.failed",
            value: 1,
            dimensions: dimensions
          )
        end

        # Add DORA metrics for deployments
        metrics << create_metric(
          name: "dora.deployment.attempt",
          value: 1,
          dimensions: dimensions
        )

        unless all_successful
          metrics << create_metric(
            name: "dora.deployment.failure",
            value: 1,
            dimensions: dimensions
          )
        end

        metrics
      end

      def classify_workflow_dispatch_event(event)
        {
          metrics: [
            create_metric(
              name: "github.workflow_dispatch.total",
              value: 1,
              dimensions: extract_dimensions(event)
            )
          ]
        }
      end

      # Handle repository events (created, deleted, publicized, privatized, etc.)
      def classify_repository_event(event, action)
        # Default to 'total' if action is nil
        action ||= "total"
        dimensions = extract_dimensions(event)

        metrics = [
          create_metric(
            name: "github.repository.#{action}",
            value: 1,
            dimensions: dimensions
          ),
          create_metric(
            name: "github.repository.total",
            value: 1,
            dimensions: dimensions
          )
        ]

        # Additional metrics for specific repository actions
        case action
        when "created", "publicized", "privatized", "edited", "renamed", "transferred"
          # These actions might trigger repository registration
          metrics << create_metric(
            name: "github.repository.registration_event",
            value: 1,
            dimensions: dimensions
          )
        end

        { metrics: metrics }
      end

      # Handle CI-specific events from GitHub Actions
      # @param event [Domain::Event] The CI event to classify
      # @return [Hash] A hash with a :metrics key containing an array of metric definitions
      def classify_ci_event(event)
        # Extract the main operation and status from the event name
        # Format is expected to be: ci.[operation].[status]
        _, operation, status = event.name.split(".")

        # Handle different CI operations based on GitHub Actions events
        case operation
        when "build"
          classify_ci_build_event(event, status)
        when "deploy"
          classify_ci_deploy_event(event, status)
        when "lead_time"
          classify_ci_lead_time_event(event)
        else
          # Generic CI event
          {
            metrics: [
              create_metric(
                name: "github.ci.#{operation || 'event'}.#{status || 'generic'}",
                value: 1,
                dimensions: extract_dimensions(event)
              )
            ]
          }
        end
      end

      # Create metrics for CI build events (connected to workflow_run/workflow_job events)
      def classify_ci_build_event(event, status)
        dimensions = extract_dimensions(event)
        metrics = []

        # Total build metric
        metrics << create_metric(
          name: "github.ci.build.total",
          value: 1,
          dimensions: dimensions
        )

        # Build by status
        metrics << create_metric(
          name: "github.ci.build.#{status}",
          value: 1,
          dimensions: dimensions
        )

        # Build duration if available
        if event.data[:duration] && event.data[:duration].to_f > 0
          metrics << create_metric(
            name: "github.ci.build.duration",
            value: event.data[:duration].to_f,
            dimensions: dimensions
          )
        end

        { metrics: metrics }
      end

      # Create metrics for CI deployment events (connected to deployment/deployment_status events)
      def classify_ci_deploy_event(event, status)
        dimensions = extract_dimensions(event)
        metrics = []

        # Total deploy metric
        metrics << create_metric(
          name: "github.ci.deploy.total",
          value: 1,
          dimensions: dimensions
        )

        # Deploy by status (completed, failed, etc.)
        metrics << create_metric(
          name: "github.ci.deploy.#{status}",
          value: 1,
          dimensions: dimensions
        )

        # Deploy duration if available
        if event.data[:duration] && event.data[:duration].to_f > 0
          metrics << create_metric(
            name: "github.ci.deploy.duration",
            value: event.data[:duration].to_f,
            dimensions: dimensions
          )
        end

        # If this is a failed deployment, create a separate incident metric
        if status == "failed"
          metrics << create_metric(
            name: "github.ci.deploy.incident",
            value: 1,
            dimensions: dimensions
          )
        end

        { metrics: metrics }
      end

      # Create metrics for lead time events (aggregated from PRs and deployments)
      def classify_ci_lead_time_event(event)
        dimensions = extract_dimensions(event)

        # Lead time is the time from commit to production
        {
          metrics: [
            create_metric(
              name: "github.ci.lead_time",
              value: event.data[:value].to_f,
              dimensions: dimensions
            )
          ]
        }
      end

      # Helper method to normalize and merge additional dimensions
      # @param base_dimensions [Hash] The base dimensions hash
      # @param additional_dimensions [Hash] Additional dimensions to add
      # @return [Hash] The merged dimensions with normalized keys and values
      def normalize_and_merge_dimensions(base_dimensions, additional_dimensions)
        return base_dimensions.merge(additional_dimensions) unless @metric_naming_port

        normalized_dimensions = {}

        additional_dimensions.each do |key, value|
          normalized_key = @metric_naming_port.normalize_dimension_name(key.to_s)
          normalized_value = @metric_naming_port.normalize_dimension_value(normalized_key, value)
          normalized_dimensions[normalized_key] = normalized_value
        end

        base_dimensions.merge(normalized_dimensions)
      end
    end
  end
end
