# ReflexAgent Code Level Diagram

This diagram provides a code-level view of the event processing pipeline in ReflexAgent, showing the classes and their relationships.

## Event Processing Pipeline (Code Level)

```mermaid
classDiagram
    class WebhooksController {
        +create()
        -enqueue_event()
    }
    
    class RawEventJob {
        +perform(event_data)
        -process_event()
    }
    
    class ProcessEvent {
        +execute(raw_event)
        -classify_event()
        -extract_dimensions()
        -store_event()
    }
    
    class GithubEventClassifier {
        +classify(raw_event)
        +relevant?(raw_event)
        -determine_event_type()
    }
    
    class DimensionExtractor {
        +extract_dimensions(event_data, type)
        -extract_commit_dimensions()
        -extract_pr_dimensions()
        -extract_issue_dimensions()
    }
    
    class Event {
        +source
        +type
        +dimensions
        +raw_data
        +timestamp
        +validate()
    }
    
    class MetricCalculationJob {
        +perform(event_id)
        -calculate_metrics()
    }
    
    class CalculateMetrics {
        +execute(event)
        -determine_metric_types()
        -compute_metrics()
        -store_metrics()
        -trigger_anomaly_detection()
    }
    
    class Metric {
        +type
        +value
        +dimensions
        +timestamp
        +event_id
        +validate()
    }
    
    class DetectAnomalies {
        +execute(metric)
        -check_thresholds()
        -compare_historical_values()
        -create_alert_if_needed()
        -trigger_notification()
    }
    
    class Alert {
        +metric_id
        +severity
        +message
        +timestamp
        +acknowledged
        +validate()
    }
    
    class SendNotification {
        +execute(alert)
        -format_notification()
        -send_to_channels()
    }
    
    class EventRepository {
        +store(event)
        +find(id)
        +find_by_dimensions(dimensions)
    }
    
    class MetricRepository {
        +store(metric)
        +find(id)
        +find_by_dimensions(dimensions)
        +find_historical(metric_type, dimensions, timeframe)
    }
    
    class AlertRepository {
        +store(alert)
        +find(id)
        +find_unacknowledged()
    }
    
    class SlackNotifier {
        +send(notification)
        -format_slack_message()
        -post_to_channel()
    }
    
    class EmailNotifier {
        +send(notification)
        -format_email()
        -send_mail()
    }

    WebhooksController --> RawEventJob : enqueues
    RawEventJob --> ProcessEvent : uses
    ProcessEvent --> GithubEventClassifier : uses
    ProcessEvent --> DimensionExtractor : uses
    ProcessEvent --> Event : creates
    ProcessEvent --> EventRepository : uses
    ProcessEvent --> MetricCalculationJob : enqueues
    
    MetricCalculationJob --> CalculateMetrics : uses
    CalculateMetrics --> Event : reads
    CalculateMetrics --> Metric : creates
    CalculateMetrics --> MetricRepository : uses
    CalculateMetrics --> DetectAnomalies : triggers
    
    DetectAnomalies --> Metric : analyzes
    DetectAnomalies --> MetricRepository : uses historical data
    DetectAnomalies --> Alert : creates
    DetectAnomalies --> AlertRepository : uses
    DetectAnomalies --> SendNotification : triggers
    
    SendNotification --> Alert : reads
    SendNotification --> SlackNotifier : uses
    SendNotification --> EmailNotifier : uses
```

This code-level diagram illustrates the classes and their relationships involved in the event processing pipeline, from receiving an event via webhook, through processing, metric calculation, anomaly detection, to sending notifications. 

The class diagram aligns with the hexagonal architecture pattern:
- Core domain classes (Event, Metric, Alert, use cases)
- Adapters (repositories, notifiers)
- Clear flow of control and data through the system

This detailed view helps developers understand the concrete implementation of the event processing pipeline within the architectural context provided by the higher-level C4 diagrams. 