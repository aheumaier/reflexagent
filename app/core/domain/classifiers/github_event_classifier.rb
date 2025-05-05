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

        {
          metrics: [
            # Count of push events
            create_metric(
              name: "github.push.total",
              value: 1,
              dimensions: dimensions
            ),
            # Count of commits in this push
            create_metric(
              name: "github.push.commits",
              value: @dimension_extractor ? @dimension_extractor.extract_commit_count(event) : 1,
              dimensions: dimensions
            ),
            # Track unique authors
            create_metric(
              name: "github.push.unique_authors",
              value: 1,
              dimensions: dimensions.merge(
                author: @dimension_extractor ? @dimension_extractor.extract_author(event) : "unknown"
              )
            ),
            # Track commits by branch
            create_metric(
              name: "github.push.branch_activity",
              value: 1,
              dimensions: dimensions.merge(
                branch: @dimension_extractor ? @dimension_extractor.extract_branch(event) : "unknown"
              )
            )
          ]
        }
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
