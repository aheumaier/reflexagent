# Checklist for Implementing New Data Source Adapters

This document provides a comprehensive checklist for implementing new data source adapters in ReflexAgent, with a focus on proper metric naming and dimension extraction.

## Pre-Implementation

- [ ] **Research source system**
  - [ ] Document event types provided by the source system
  - [ ] Map source system events to our domain concepts
  - [ ] Identify required authentication mechanisms
  - [ ] Determine webhook payload formats or API response structures

- [ ] **Update constants**
  - [ ] Add new source to `Domain::Constants::MetricNames::Sources`
  - [ ] Add any source-specific entities to `Domain::Constants::MetricNames::Entities`
  - [ ] Add any source-specific actions to `Domain::Constants::MetricNames::Actions`

- [ ] **Design metric names**
  - [ ] Define all metrics to be generated from this source
  - [ ] Ensure all metric names follow the `[source].[entity].[action].[detail]` format
  - [ ] Verify metric names are consistent with existing metrics for similar concepts
  - [ ] Document new metrics in appropriate documentation

## Core Implementation

- [ ] **Create event classifier**
  - [ ] Create a new classifier class under `app/core/domain/classifiers/`
  - [ ] Inherit from `BaseClassifier` or implement the classifier interface
  - [ ] Implement the `classify` method to handle events from the new source
  - [ ] Use `Domain::Constants::MetricNames.build` method for all metric names

- [ ] **Create dimension extractor**
  - [ ] Create a dimension extractor for the new source
  - [ ] Use constants from `Domain::Constants::DimensionConstants` for all dimension names
  - [ ] Implement standard dimension normalization (repository names, dates, etc.)
  - [ ] Ensure all required dimensions are extracted

- [ ] **Update factory methods**
  - [ ] Update `EventClassifierFactory` to instantiate the new classifier
  - [ ] Update `DimensionExtractorFactory` to instantiate the new extractor

## Adapter Implementation

- [ ] **Create webhook controller or API client**
  - [ ] Implement authentication and validation
  - [ ] Convert source-specific payloads to our domain `Event` format
  - [ ] Set appropriate source name in events

- [ ] **Add tests**
  - [ ] Unit tests for the classifier with sample payloads
  - [ ] Unit tests for the dimension extractor
  - [ ] Integration tests for the webhook endpoint or API client
  - [ ] End-to-end tests for the complete flow

## Verification and Documentation

- [ ] **Verify metric naming**
  - [ ] Manually test with sample events
  - [ ] Verify all generated metrics follow naming convention
  - [ ] Check all dimensions are correctly populated
  - [ ] Compare metrics with existing sources for consistency

- [ ] **Update documentation**
  - [ ] Add new source to metrics naming convention document
  - [ ] Document source-specific dimensions or special handling
  - [ ] Update dashboard documentation if applicable
  - [ ] Create webhook setup instructions if applicable

## Implementation Example

Below is a template for a new source classifier:

```ruby
# frozen_string_literal: true

module Domain
  module Classifiers
    class NewSourceEventClassifier < BaseClassifier
      def classify(event)
        metrics = []
        
        # Extract primary event type from the event
        event_type = extract_event_type(event)
        action = extract_action(event)
        
        # Build standardized dimensions
        dimensions = extract_dimensions(event)
        
        # Classify based on event type
        case event_type
        when "pull_request"
          classify_pull_request_event(event, action, metrics, dimensions)
        when "push"
          classify_push_event(event, metrics, dimensions)
        # Add other event types...
        else
          # Generic event
          metrics << create_metric(
            name: Domain::Constants::MetricNames.build(
              source: Domain::Constants::MetricNames::Sources::NEW_SOURCE,
              entity: event_type,
              action: action || Domain::Constants::MetricNames::Actions::TOTAL
            ),
            value: 1,
            dimensions: dimensions
          )
        end
        
        { metrics: metrics }
      end
      
      private
      
      def extract_dimensions(event)
        if @dimension_extractor
          @dimension_extractor.extract_dimensions(event)
        else
          # Return basic dimensions if no extractor is provided
          Domain::Constants::DimensionConstants.build_standard_dimensions(
            source: Domain::Constants::MetricNames::Sources::NEW_SOURCE,
            repository: extract_repository(event),
            author: extract_author(event)
          )
        end
      end
      
      def classify_pull_request_event(event, action, metrics, dimensions)
        # Use standardized method to build metric name
        metrics << create_metric(
          name: Domain::Constants::MetricNames.build(
            source: Domain::Constants::MetricNames::Sources::NEW_SOURCE,
            entity: Domain::Constants::MetricNames::Entities::PULL_REQUEST,
            action: Domain::Constants::MetricNames::Actions::TOTAL
          ),
          value: 1, 
          dimensions: dimensions.merge(
            Domain::Constants::DimensionConstants::Classification::ACTION => action
          )
        )
        
        # Add specific action metric
        metrics << create_metric(
          name: Domain::Constants::MetricNames.build(
            source: Domain::Constants::MetricNames::Sources::NEW_SOURCE,
            entity: Domain::Constants::MetricNames::Entities::PULL_REQUEST,
            action: action
          ),
          value: 1,
          dimensions: dimensions
        )
        
        # Add author metric
        metrics << create_metric(
          name: Domain::Constants::MetricNames.build(
            source: Domain::Constants::MetricNames::Sources::NEW_SOURCE,
            entity: Domain::Constants::MetricNames::Entities::PULL_REQUEST,
            action: Domain::Constants::MetricNames::Actions::BY_AUTHOR
          ),
          value: 1,
          dimensions: dimensions
        )
      end
      
      # Additional helper methods...
    end
  end
end
```

## Related Documents

- [Metrics Naming Convention](metrics_naming_convention.md)
- [Dimension Standards](dimension_standards.md)
- [ADR-0005: Metric Naming Standardization](ADR/ADR-0005-metric-naming-convention.md)
- [Metric Constants](metric_constants.rb)
- [Dimension Constants](../core/domain/constants/dimension_constants.rb) 