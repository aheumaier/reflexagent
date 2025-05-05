# frozen_string_literal: true

module Domain
  module Classifiers
    # The MetricClassifier is responsible for analyzing events and determining
    # which metrics should be created from them.
    #
    # It maps different event types to appropriate metrics with their dimensions,
    # creating a configurable way to generate metrics from incoming events.
    class MetricClassifier
      attr_reader :github_classifier, :jira_classifier, :gitlab_classifier,
                  :bitbucket_classifier, :ci_classifier, :task_classifier,
                  :generic_classifier, :dimension_extractor

      # Initialize the classifier with optional source-specific classifiers
      # @param classifiers [Hash] A hash of source-specific classifiers
      # @param dimension_extractor [Domain::Extractors::DimensionExtractor] Dimension extractor
      def initialize(classifiers = {}, dimension_extractor = nil)
        @dimension_extractor = dimension_extractor || Domain::Extractors::DimensionExtractor.new

        # Initialize source-specific classifiers
        @github_classifier = classifiers[:github]
        @jira_classifier = classifiers[:jira]
        @gitlab_classifier = classifiers[:gitlab]
        @bitbucket_classifier = classifiers[:bitbucket]
        @ci_classifier = classifiers[:ci]
        @task_classifier = classifiers[:task]
        @generic_classifier = classifiers[:generic]
      end

      # Analyzes an event and returns a classification of metrics to be created
      #
      # @param event [Domain::Event] The event to classify
      # @return [Hash] A hash with a :metrics key containing an array of metric definitions
      def classify_event(event)
        event_type = event.name

        # Dispatch to the appropriate handler based on the event type pattern
        case event_type
        when /^github\./
          delegate_to_github_classifier(event)
        when /^jira\./
          delegate_to_jira_classifier(event)
        when /^gitlab\./
          delegate_to_gitlab_classifier(event)
        when /^bitbucket\./
          delegate_to_bitbucket_classifier(event)
        when /^ci\./
          delegate_to_ci_classifier(event)
        when /^task\./
          delegate_to_task_classifier(event)
        else
          delegate_to_generic_classifier(event)
        end
      end

      private

      # Delegation methods to source-specific classifiers

      def delegate_to_github_classifier(event)
        if @github_classifier
          @github_classifier.classify(event)
        else
          classify_github_event(event)
        end
      end

      def delegate_to_jira_classifier(event)
        if @jira_classifier
          @jira_classifier.classify(event)
        else
          classify_jira_event(event)
        end
      end

      def delegate_to_gitlab_classifier(event)
        if @gitlab_classifier
          @gitlab_classifier.classify(event)
        else
          classify_gitlab_event(event)
        end
      end

      def delegate_to_bitbucket_classifier(event)
        if @bitbucket_classifier
          @bitbucket_classifier.classify(event)
        else
          classify_bitbucket_event(event)
        end
      end

      def delegate_to_ci_classifier(event)
        if @ci_classifier
          @ci_classifier.classify(event)
        else
          classify_ci_event(event)
        end
      end

      def delegate_to_task_classifier(event)
        if @task_classifier
          @task_classifier.classify(event)
        else
          classify_task_event(event)
        end
      end

      def delegate_to_generic_classifier(event)
        if @generic_classifier
          @generic_classifier.classify(event)
        else
          classify_generic_event(event)
        end
      end

      # Fallback classification methods
      # These methods will be overridden or replaced in the future with specific implementations

      # Fallback method for GitHub events when no GitHub classifier is provided
      # @param event [Domain::Event] GitHub event to classify
      # @return [Hash] Classification result
      def classify_github_event(event)
        # Default implementation - will be enhanced in the future
        { metrics: [] }
      end

      # Fallback method for Jira events when no Jira classifier is provided
      # @param event [Domain::Event] Jira event to classify
      # @return [Hash] Classification result
      def classify_jira_event(event)
        event_subtype = event.name.sub("jira.", "")

        case event_subtype
        when /^issue_(created|updated|resolved|deleted)$/
          action = ::Regexp.last_match(1)
          {
            metrics: [
              # Total issues
              {
                name: "jira.issue.total",
                value: 1,
                dimensions: extract_jira_dimensions(event).merge(action: action)
              },
              # Issues by action type
              {
                name: "jira.issue.#{action}",
                value: 1,
                dimensions: extract_jira_dimensions(event)
              },
              # Issues by type
              {
                name: "jira.issue.by_type",
                value: 1,
                dimensions: extract_jira_dimensions(event).merge(
                  issue_type: extract_jira_issue_type(event),
                  action: action
                )
              }
            ]
          }
        when /^sprint_(started|closed)$/
          action = ::Regexp.last_match(1)
          {
            metrics: [
              {
                name: "jira.sprint.#{action}",
                value: 1,
                dimensions: extract_jira_dimensions(event)
              }
            ]
          }
        else
          # Generic Jira event
          {
            metrics: [
              {
                name: "jira.#{event_subtype}.total",
                value: 1,
                dimensions: extract_jira_dimensions(event)
              }
            ]
          }
        end
      end

      # Fallback method for GitLab events when no GitLab classifier is provided
      # @param event [Domain::Event] GitLab event to classify
      # @return [Hash] Classification result
      def classify_gitlab_event(event)
        # Default implementation - will be enhanced in the future
        { metrics: [] }
      end

      # Fallback method for Bitbucket events when no Bitbucket classifier is provided
      # @param event [Domain::Event] Bitbucket event to classify
      # @return [Hash] Classification result
      def classify_bitbucket_event(event)
        # Default implementation - will be enhanced in the future
        { metrics: [] }
      end

      # Fallback method for CI events when no CI classifier is provided
      # @param event [Domain::Event] CI event to classify
      # @return [Hash] Classification result
      def classify_ci_event(event)
        # Default implementation - will be enhanced in the future
        { metrics: [] }
      end

      # Fallback method for Task events when no Task classifier is provided
      # @param event [Domain::Event] Task event to classify
      # @return [Hash] Classification result
      def classify_task_event(event)
        # Default implementation - will be enhanced in the future
        { metrics: [] }
      end

      # Fallback method for generic events when no Generic classifier is provided
      # @param event [Domain::Event] Event to classify
      # @return [Hash] Classification result
      def classify_generic_event(event)
        # Default implementation - will be enhanced in the future
        { metrics: [] }
      end

      # Dimension extraction helpers

      def extract_jira_dimensions(event)
        data = event.data
        {
          project: data.dig(:issue, :fields, :project, :key) ||
            data.dig(:project, :key) ||
            "unknown",
          source: event.source
        }
      end

      def extract_jira_issue_type(event)
        event.data.dig(:issue, :fields, :issuetype, :name) || "unknown"
      end
    end
  end
end
