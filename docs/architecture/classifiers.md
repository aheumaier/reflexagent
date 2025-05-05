# Event Classification Architecture

## Overview
The event classification system in ReflexAgent follows a delegation-based architecture to improve maintainability and extensibility. This document describes the architecture and components of the event classification system.

## Components

### 1. MetricClassifier
The `Domain::MetricClassifier` is the entry point for event classification. It is responsible for:
- Identifying the source of events (GitHub, Jira, Bitbucket, etc.)
- Delegating to the appropriate source-specific classifier
- Providing fallback implementations when specific classifiers are not available

### 2. Source-specific Classifiers
Each source has its own dedicated classifier:
- `Domain::Classifiers::GithubEventClassifier`: Handles GitHub events
- `Domain::Classifiers::JiraEventClassifier`: Handles Jira events
- `Domain::Classifiers::BitbucketEventClassifier`: Handles Bitbucket events

Each classifier implements a `classify` method that takes an event and returns a hash with a `:metrics` key containing an array of metric definitions.

### 3. BaseClassifier
The `Domain::Classifiers::BaseClassifier` defines the common interface and utility methods that all source-specific classifiers should implement.

### 4. DimensionExtractor
The `Domain::Extractors::DimensionExtractor` is responsible for extracting dimensions from events. It provides methods for each source type to extract relevant dimensions.

## Usage

### Instantiating the Classifier
The MetricClassifier should be instantiated with source-specific classifiers and a dimension extractor:

```ruby
github_classifier = Domain::Classifiers::GithubEventClassifier.new(dimension_extractor)
jira_classifier = Domain::Classifiers::JiraEventClassifier.new(dimension_extractor)
bitbucket_classifier = Domain::Classifiers::BitbucketEventClassifier.new(dimension_extractor)

classifier = Domain::MetricClassifier.new(
  github_classifier: github_classifier,
  jira_classifier: jira_classifier,
  bitbucket_classifier: bitbucket_classifier,
  dimension_extractor: dimension_extractor
)
```

### Classifying Events
To classify an event, call the `classify_event` method on the MetricClassifier:

```ruby
event = Domain::Event.new(name: "github.push", source: "github", data: {...})
classification = classifier.classify_event(event)
# => { metrics: [ { name: "github.push.total", value: 1, dimensions: {...} }, ... ] }
```

## Adding New Source Classifiers

To add a new source classifier:

1. Create a new class that extends `Domain::Classifiers::BaseClassifier`
2. Implement the `classify` method
3. Update the `MetricClassifier` to delegate to the new classifier
4. Update dependency injection to wire the new classifier

## Testing

Classifiers can be tested independently by creating test events and verifying the output metrics:

```ruby
classifier = Domain::Classifiers::GithubEventClassifier.new(dimension_extractor)
event = Domain::Event.new(name: "github.push", source: "github", data: {...})
result = classifier.classify(event)
expect(result[:metrics]).to include(a_hash_including(name: "github.push.total"))
``` 