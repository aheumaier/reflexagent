# frozen_string_literal: true

module Domain
  # The MetricClassifier is responsible for analyzing events and determining
  # which metrics should be created from them.
  #
  # It maps different event types to appropriate metrics with their dimensions,
  # creating a configurable way to generate metrics from incoming events.
  class MetricClassifier
    attr_reader :github_classifier, :jira_classifier, :bitbucket_classifier, :dimension_extractor

    # Initialize the classifier with optional source-specific classifiers
    # @param github_classifier [Domain::Classifiers::GithubEventClassifier] GitHub event classifier
    # @param jira_classifier [Domain::Classifiers::JiraEventClassifier] Jira event classifier
    # @param bitbucket_classifier [Domain::Classifiers::BitbucketEventClassifier] Bitbucket event classifier
    # @param dimension_extractor [Domain::Extractors::DimensionExtractor] Dimension extractor
    def initialize(github_classifier: nil, jira_classifier: nil, bitbucket_classifier: nil, dimension_extractor: nil)
      @github_classifier = github_classifier
      @jira_classifier = jira_classifier
      @bitbucket_classifier = bitbucket_classifier
      @dimension_extractor = dimension_extractor
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
      when /^bitbucket\./
        delegate_to_bitbucket_classifier(event)
      else
        classify_generic_event(event)
      end
    end

    private

    # Delegation methods to source-specific classifiers

    def delegate_to_github_classifier(event)
      if @github_classifier
        @github_classifier.classify(event)
      else
        fallback_github_classifier(event)
      end
    end

    def delegate_to_jira_classifier(event)
      if @jira_classifier
        @jira_classifier.classify(event)
      else
        fallback_jira_classifier(event)
      end
    end

    def delegate_to_bitbucket_classifier(event)
      if @bitbucket_classifier
        @bitbucket_classifier.classify(event)
      else
        fallback_bitbucket_classifier(event)
      end
    end

    # Generic event fallback when there's no specialized handler
    def classify_generic_event(event)
      # For events that don't match any specific pattern
      {
        metrics: [
          {
            name: "#{event.name}.generic",
            value: 1,
            dimensions: { source: event.source }
          }
        ]
      }
    end

    # Fallback implementations for when classifiers are not provided

    def fallback_github_classifier(event)
      # This method will be removed in the future
      # Consider adding github_classifier as a required dependency
      Rails.logger.warn("Using fallback GitHub classifier. Consider providing a proper classifier instance.")
      {
        metrics: [
          {
            name: "github.event.generic",
            value: 1,
            dimensions: { source: event.source }
          }
        ]
      }
    end

    def fallback_jira_classifier(event)
      # This method will be removed in the future
      # Consider adding jira_classifier as a required dependency
      Rails.logger.warn("Using fallback Jira classifier. Consider providing a proper classifier instance.")
      {
        metrics: [
          {
            name: "jira.event.generic",
            value: 1,
            dimensions: { source: event.source }
          }
        ]
      }
    end

    def fallback_bitbucket_classifier(event)
      # This method will be removed in the future
      # Consider adding bitbucket_classifier as a required dependency
      Rails.logger.warn("Using fallback Bitbucket classifier. Consider providing a proper classifier instance.")
      {
        metrics: [
          {
            name: "bitbucket.event.generic",
            value: 1,
            dimensions: { source: event.source }
          }
        ]
      }
    end
  end
end
