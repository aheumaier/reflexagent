# frozen_string_literal: true

module Domain
  module Classifiers
    # BaseClassifier defines the interface for all event classifiers
    # This is the parent class for all source-specific classifiers like GithubClassifier, JiraClassifier, etc.
    class BaseClassifier
      attr_reader :dimension_extractor

      # Initialize with an optional dimension extractor
      # @param dimension_extractor [Domain::Extractors::DimensionExtractor] Extractor for event dimensions
      def initialize(dimension_extractor = nil)
        @dimension_extractor = dimension_extractor
      end

      # Classify an event and return metric definitions
      # @param event [Domain::Event] The event to classify
      # @return [Hash] A hash with a :metrics key containing an array of metric definitions
      def classify(event)
        raise NotImplementedError, "Subclasses must implement classify method"
      end

      # Helper method to create a metric definition
      # @param name [String] The metric name
      # @param value [Numeric] The metric value
      # @param dimensions [Hash] The metric dimensions
      # @param timestamp [Time] Optional timestamp for the metric
      # @return [Hash] A metric definition hash
      def create_metric(name:, value:, dimensions: {}, timestamp: nil)
        metric = {
          name: name,
          value: value,
          dimensions: dimensions
        }

        # Add timestamp if provided
        metric[:timestamp] = timestamp if timestamp

        metric
      end

      # Helper method to extract event sub type and action
      # @param event [Domain::Event] The event to extract from
      # @param prefix [String] The event source prefix to remove
      # @return [Array<String>] The event sub type and action
      def extract_event_parts(event, prefix)
        # Remove the prefix (e.g., "github.") from the event name
        event_subtype = event.name.sub("#{prefix}.", "")

        # Split by dot to get event type and action
        parts = event_subtype.split(".")

        if parts.length >= 2
          [parts[0], parts[1]]
        else
          [parts[0], nil]
        end
      end
    end
  end
end
