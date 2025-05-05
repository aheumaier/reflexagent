# frozen_string_literal: true

module Domain
  module Classifiers
    # BitbucketEventClassifier is responsible for analyzing Bitbucket events and determining
    # which metrics should be created from them.
    class BitbucketEventClassifier < BaseClassifier
      # Classify a Bitbucket event and return metric definitions
      # @param event [Domain::Event] The Bitbucket event to classify
      # @return [Hash] A hash with a :metrics key containing an array of metric definitions
      def classify(event)
        # Extract the subtype from the event name (everything after "bitbucket.")
        event_subtype = event.name.sub("bitbucket.", "")

        case event_subtype
        when /^repo:push$/
          classify_push_event(event)
        when /^pullrequest:(created|approved|merged|rejected)$/
          action = ::Regexp.last_match(1)
          classify_pullrequest_event(event, action)
        else
          # Generic Bitbucket event
          {
            metrics: [
              create_metric(
                name: "bitbucket.#{event_subtype}.total",
                value: 1,
                dimensions: extract_dimensions(event)
              )
            ]
          }
        end
      end

      private

      def extract_dimensions(event)
        @dimension_extractor ? @dimension_extractor.extract_bitbucket_dimensions(event) : {}
      end

      def classify_push_event(event)
        dimensions = extract_dimensions(event)
        commit_count = @dimension_extractor ? @dimension_extractor.extract_bitbucket_commit_count(event) : 1

        {
          metrics: [
            create_metric(
              name: "bitbucket.push.total",
              value: 1,
              dimensions: dimensions
            ),
            create_metric(
              name: "bitbucket.push.commits",
              value: commit_count,
              dimensions: dimensions
            )
          ]
        }
      end

      def classify_pullrequest_event(event, action)
        dimensions = extract_dimensions(event)

        {
          metrics: [
            create_metric(
              name: "bitbucket.pullrequest.total",
              value: 1,
              dimensions: dimensions.merge(action: action)
            ),
            create_metric(
              name: "bitbucket.pullrequest.#{action}",
              value: 1,
              dimensions: dimensions
            )
          ]
        }
      end
    end
  end
end
