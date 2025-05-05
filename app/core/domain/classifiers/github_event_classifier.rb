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
        # Handle CI-specific events from GitHub
        when "ci"
          classify_ci_event(event)
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
        dimensions = extract_dimensions(event).merge(environment: environment)
        metrics = []

        # Basic deployment metrics
        metrics << create_metric(
          name: "github.deployment_status.total",
          value: 1,
          dimensions: dimensions.merge(state: state)
        )

        metrics << create_metric(
          name: "github.deployment_status.#{state}",
          value: 1,
          dimensions: dimensions
        )

        # Add CI deploy metrics for success/failure states
        if ["success", "failure", "error"].include?(state)
          # Map deployment state to CI deploy status
          ci_status = case state
                      when "success"
                        "completed"
                      when "failure", "error"
                        "failed"
                      else
                        state
                      end

          # CI deploy total metric
          metrics << create_metric(
            name: "github.ci.deploy.total",
            value: 1,
            dimensions: dimensions
          )

          # CI deploy status metric
          metrics << create_metric(
            name: "github.ci.deploy.#{ci_status}",
            value: 1,
            dimensions: dimensions
          )

          # If deployment failed, create incident metric
          if ["failure", "error"].include?(state)
            metrics << create_metric(
              name: "github.ci.deploy.incident",
              value: 1,
              dimensions: dimensions
            )
          end

          # Calculate lead time for successful deployments
          if state == "success" && event.data.dig(:deployment, :created_at)
            begin
              deployment_created = Time.parse(event.data.dig(:deployment, :created_at).to_s)
              deployment_updated = Time.parse(event.data.dig(:deployment_status, :updated_at).to_s)
              lead_time = (deployment_updated - deployment_created).to_i

              metrics << create_metric(
                name: "github.ci.lead_time",
                value: lead_time,
                dimensions: dimensions
              )
            rescue StandardError => e
              Rails.logger.error("Error calculating deployment lead time: #{e.message}")
            end
          end
        end

        { metrics: metrics }
      end

      def classify_workflow_run_event(event, action)
        # Default to 'total' if action is nil
        action ||= "total"
        conclusion = event.data.dig(:workflow_run, :conclusion) || "unknown"
        dimensions = extract_dimensions(event)
        metrics = []

        # Basic workflow_run metrics
        metrics << create_metric(
          name: "github.workflow_run.#{action}",
          value: 1,
          dimensions: dimensions
        )

        metrics << create_metric(
          name: "github.workflow_run.conclusion.#{conclusion}",
          value: 1,
          dimensions: dimensions
        )

        # Add CI build metrics for completed workflow runs
        if action == "completed"
          # Map workflow conclusions to CI build status
          ci_status = case conclusion
                      when "success"
                        "completed"
                      when "failure"
                        "failed"
                      else
                        conclusion
                      end

          # CI build total metric
          metrics << create_metric(
            name: "github.ci.build.total",
            value: 1,
            dimensions: dimensions
          )

          # CI build status metric
          metrics << create_metric(
            name: "github.ci.build.#{ci_status}",
            value: 1,
            dimensions: dimensions
          )

          # Duration if available
          if event.data.dig(:workflow_run, :run_started_at) && event.data.dig(:workflow_run, :updated_at)
            begin
              started_at = Time.parse(event.data.dig(:workflow_run, :run_started_at).to_s)
              updated_at = Time.parse(event.data.dig(:workflow_run, :updated_at).to_s)
              duration = (updated_at - started_at).to_i

              metrics << create_metric(
                name: "github.ci.build.duration",
                value: duration,
                dimensions: dimensions
              )
            rescue StandardError => e
              Rails.logger.error("Error calculating workflow duration: #{e.message}")
            end
          end
        end

        { metrics: metrics }
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
    end
  end
end
