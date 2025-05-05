# frozen_string_literal: true

module Domain
  module Classifiers
    # GithubEventClassifier is responsible for analyzing GitHub events and determining
    # which metrics should be created from them.
    class GithubEventClassifier < BaseClassifier
      # Classify a GitHub event and return metric definitions
      # @param event [Domain::Event] The GitHub event to classify
      # @return [Hash] A hash with a :metrics key containing an array of metric definitions
      def classify(event)
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
        else
          # Generic GitHub event
          {
            metrics: [
              create_metric(
                name: "github.#{event_name}.#{action || 'total'}",
                value: 1,
                dimensions: extract_dimensions(event)
              )
            ]
          }
        end
      end

      private

      def extract_dimensions(event)
        @dimension_extractor ? @dimension_extractor.extract_github_dimensions(event) : {}
      end

      def classify_push_event(event)
        dimensions = extract_dimensions(event)
        metrics = []

        # Basic push metrics (existing)
        metrics << create_metric(
          name: "github.push.total",
          value: 1,
          dimensions: dimensions
        )

        metrics << create_metric(
          name: "github.push.commits",
          value: @dimension_extractor ? @dimension_extractor.extract_commit_count(event) : 1,
          dimensions: dimensions
        )

        metrics << create_metric(
          name: "github.push.unique_authors",
          value: 1,
          dimensions: dimensions.merge(
            author: @dimension_extractor ? @dimension_extractor.extract_author(event) : "unknown"
          )
        )

        metrics << create_metric(
          name: "github.push.branch_activity",
          value: 1,
          dimensions: dimensions.merge(
            branch: @dimension_extractor ? @dimension_extractor.extract_branch(event) : "unknown"
          )
        )

        # Enhanced metrics for conventional commits
        if @dimension_extractor && event.data[:commits]
          # Process each commit for conventional commit metrics
          event.data[:commits].each do |commit|
            commit_parts = @dimension_extractor.extract_conventional_commit_parts(commit)

            # Only track conventional commits with proper type
            next unless commit_parts[:commit_conventional]

            # Track by commit type (feat, fix, chore, etc.)
            metrics << create_metric(
              name: "github.push.commit_type",
              value: 1,
              dimensions: dimensions.merge(
                type: commit_parts[:commit_type],
                scope: commit_parts[:commit_scope] || "none"
              )
            )

            # Track breaking changes separately
            next unless commit_parts[:commit_breaking]

            metrics << create_metric(
              name: "github.push.breaking_change",
              value: 1,
              dimensions: dimensions.merge(
                type: commit_parts[:commit_type],
                scope: commit_parts[:commit_scope] || "none",
                author: @dimension_extractor.extract_author(event)
              )
            )
          end

          # Extract file changes and add file-based metrics
          file_changes = @dimension_extractor.extract_file_changes(event)

          # Track overall file changes
          metrics << create_metric(
            name: "github.push.files_added",
            value: file_changes[:files_added],
            dimensions: dimensions
          )

          metrics << create_metric(
            name: "github.push.files_modified",
            value: file_changes[:files_modified],
            dimensions: dimensions
          )

          metrics << create_metric(
            name: "github.push.files_removed",
            value: file_changes[:files_removed],
            dimensions: dimensions
          )

          # Track top directory changes
          if file_changes[:top_directory].present?
            metrics << create_metric(
              name: "github.push.directory_hotspot",
              value: file_changes[:top_directory_count],
              dimensions: dimensions.merge(
                directory: file_changes[:top_directory]
              )
            )

            # Track each directory in the hotspot list
            if file_changes[:directory_hotspots].present?
              file_changes[:directory_hotspots].each do |dir, count|
                metrics << create_metric(
                  name: "github.push.directory_changes",
                  value: count,
                  dimensions: dimensions.merge(directory: dir)
                )
              end
            end
          end

          # Track top file extension changes
          if file_changes[:top_extension].present?
            metrics << create_metric(
              name: "github.push.filetype_hotspot",
              value: file_changes[:top_extension_count],
              dimensions: dimensions.merge(
                filetype: file_changes[:top_extension]
              )
            )

            # Track each extension in the hotspot list
            if file_changes[:extension_hotspots].present?
              file_changes[:extension_hotspots].each do |ext, count|
                metrics << create_metric(
                  name: "github.push.filetype_changes",
                  value: count,
                  dimensions: dimensions.merge(filetype: ext)
                )
              end
            end
          end

          # Track code volume metrics
          code_volume = @dimension_extractor.extract_code_volume(event)
          if code_volume[:code_additions] > 0 || code_volume[:code_deletions] > 0
            metrics << create_metric(
              name: "github.push.code_additions",
              value: code_volume[:code_additions],
              dimensions: dimensions
            )

            metrics << create_metric(
              name: "github.push.code_deletions",
              value: code_volume[:code_deletions],
              dimensions: dimensions
            )

            metrics << create_metric(
              name: "github.push.code_churn",
              value: code_volume[:code_churn],
              dimensions: dimensions
            )
          end
        end

        { metrics: metrics }
      end

      def classify_pull_request_event(event, action)
        # Default to 'total' if action is nil
        action ||= "total"
        dimensions = extract_dimensions(event)

        {
          metrics: [
            # Total PRs
            create_metric(
              name: "github.pull_request.total",
              value: 1,
              dimensions: dimensions.merge(action: action)
            ),
            # PR action count (opened, closed, merged, etc.)
            create_metric(
              name: "github.pull_request.#{action}",
              value: 1,
              dimensions: dimensions
            ),
            # Track PR by author
            create_metric(
              name: "github.pull_request.by_author",
              value: 1,
              dimensions: dimensions.merge(
                author: @dimension_extractor ? @dimension_extractor.extract_author(event) : "unknown",
                action: action
              )
            )
          ]
        }
      end

      def classify_issues_event(event, action)
        # Default to 'total' if action is nil
        action ||= "total"
        dimensions = extract_dimensions(event)

        {
          metrics: [
            # Total issues
            create_metric(
              name: "github.issues.total",
              value: 1,
              dimensions: dimensions.merge(action: action)
            ),
            # Issue action count
            create_metric(
              name: "github.issues.#{action}",
              value: 1,
              dimensions: dimensions
            ),
            # Issues by author
            create_metric(
              name: "github.issues.by_author",
              value: 1,
              dimensions: dimensions.merge(
                author: @dimension_extractor ? @dimension_extractor.extract_author(event) : "unknown",
                action: action
              )
            )
          ]
        }
      end

      def classify_check_run_event(event, action)
        # Default to 'total' if action is nil
        action ||= "total"

        {
          metrics: [
            create_metric(
              name: "github.check_run.#{action}",
              value: 1,
              dimensions: extract_dimensions(event)
            )
          ]
        }
      end

      def classify_check_suite_event(event, action)
        # Default to 'total' if action is nil
        action ||= "total"

        {
          metrics: [
            create_metric(
              name: "github.check_suite.#{action}",
              value: 1,
              dimensions: extract_dimensions(event)
            )
          ]
        }
      end

      def classify_create_event(event)
        ref_type = event.data[:ref_type] || "unknown"
        dimensions = extract_dimensions(event)

        {
          metrics: [
            create_metric(
              name: "github.create.total",
              value: 1,
              dimensions: dimensions
            ),
            create_metric(
              name: "github.create.#{ref_type}",
              value: 1,
              dimensions: dimensions
            )
          ]
        }
      end

      def classify_delete_event(event)
        ref_type = event.data[:ref_type] || "unknown"
        dimensions = extract_dimensions(event)

        {
          metrics: [
            create_metric(
              name: "github.delete.total",
              value: 1,
              dimensions: dimensions
            ),
            create_metric(
              name: "github.delete.#{ref_type}",
              value: 1,
              dimensions: dimensions
            )
          ]
        }
      end

      def classify_deployment_event(event)
        environment = event.data.dig(:deployment, :environment) || "unknown"
        dimensions = extract_dimensions(event)

        {
          metrics: [
            create_metric(
              name: "github.deployment.total",
              value: 1,
              dimensions: dimensions
            ),
            create_metric(
              name: "github.deployment.environment",
              value: 1,
              dimensions: dimensions.merge(environment: environment)
            )
          ]
        }
      end

      def classify_deployment_status_event(event, action)
        environment = event.data.dig(:deployment, :environment) || "unknown"
        state = event.data.dig(:deployment_status, :state) || "unknown"
        dimensions = extract_dimensions(event)

        {
          metrics: [
            create_metric(
              name: "github.deployment_status.total",
              value: 1,
              dimensions: dimensions.merge(
                environment: environment,
                state: state
              )
            ),
            create_metric(
              name: "github.deployment_status.#{state}",
              value: 1,
              dimensions: dimensions.merge(environment: environment)
            )
          ]
        }
      end

      def classify_workflow_run_event(event, action)
        # Default to 'total' if action is nil
        action ||= "total"
        conclusion = event.data.dig(:workflow_run, :conclusion) || "unknown"
        dimensions = extract_dimensions(event)

        {
          metrics: [
            create_metric(
              name: "github.workflow_run.#{action}",
              value: 1,
              dimensions: dimensions
            ),
            create_metric(
              name: "github.workflow_run.conclusion.#{conclusion}",
              value: 1,
              dimensions: dimensions
            )
          ]
        }
      end

      def classify_workflow_job_event(event, action)
        # Default to 'total' if action is nil
        action ||= "total"
        conclusion = event.data.dig(:workflow_job, :conclusion) || "unknown"
        dimensions = extract_dimensions(event)

        {
          metrics: [
            create_metric(
              name: "github.workflow_job.#{action}",
              value: 1,
              dimensions: dimensions
            ),
            create_metric(
              name: "github.workflow_job.conclusion.#{conclusion}",
              value: 1,
              dimensions: dimensions
            )
          ]
        }
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
    end
  end
end
