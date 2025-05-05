# frozen_string_literal: true

module Domain
  module Classifiers
    # JiraEventClassifier is responsible for analyzing Jira events and determining
    # which metrics should be created from them.
    class JiraEventClassifier < BaseClassifier
      # Classify a Jira event and return metric definitions
      # @param event [Domain::Event] The Jira event to classify
      # @return [Hash] A hash with a :metrics key containing an array of metric definitions
      def classify(event)
        # Extract the subtype from the event name (everything after "jira.")
        event_subtype = event.name.sub("jira.", "")

        case event_subtype
        when /^issue_(created|updated|resolved|deleted)$/
          action = ::Regexp.last_match(1)
          classify_issue_event(event, action)
        when /^sprint_(started|closed)$/
          action = ::Regexp.last_match(1)
          classify_sprint_event(event, action)
        else
          # Generic Jira event
          {
            metrics: [
              create_metric(
                name: "jira.#{event_subtype}.total",
                value: 1,
                dimensions: extract_dimensions(event)
              )
            ]
          }
        end
      end

      private

      def extract_dimensions(event)
        @dimension_extractor ? @dimension_extractor.extract_jira_dimensions(event) : {}
      end

      def classify_issue_event(event, action)
        dimensions = extract_dimensions(event)
        issue_type = @dimension_extractor ? @dimension_extractor.extract_jira_issue_type(event) : "unknown"

        {
          metrics: [
            # Total issues
            create_metric(
              name: "jira.issue.total",
              value: 1,
              dimensions: dimensions.merge(action: action)
            ),
            # Issues by action type
            create_metric(
              name: "jira.issue.#{action}",
              value: 1,
              dimensions: dimensions
            ),
            # Issues by type
            create_metric(
              name: "jira.issue.by_type",
              value: 1,
              dimensions: dimensions.merge(
                issue_type: issue_type,
                action: action
              )
            )
          ]
        }
      end

      def classify_sprint_event(event, action)
        dimensions = extract_dimensions(event)

        {
          metrics: [
            create_metric(
              name: "jira.sprint.#{action}",
              value: 1,
              dimensions: dimensions
            )
          ]
        }
      end
    end
  end
end
