# Architecture Documentation for ReflexAgent

This document provides an overview of the Hexagonal (Ports & Adapters) architecture implemented in ReflexAgent, guiding developers through the core concepts, directory layout, and key guidelines.

> **Navigation**: [Documentation Index](../README.md) | [Domain Documentation](../domain/README.md) | [Technical Documentation](../technical/README.md) | [Operations Documentation](../operations/README.md)

## 1. Architectural Overview

ReflexAgent implements the Hexagonal/Ports & Adapters pattern to achieve:

- **Separation of Concerns**: Business logic (core) is isolated from frameworks and infrastructure.
- **Testability**: Core use cases and domain models are framework-agnostic and can be unit tested with mock ports.
- **Replaceability**: Infrastructure components (Rails, Redis, Sidekiq, Slack, Python services) can be swapped by implementing different adapters without touching core logic.

### 1.1 High-Level Architecture Diagram

```mermaid
flowchart TB
  subgraph External World
    GH[GitHub]
    JIRA[Jira]
    BB[Bitbucket]
    Slack[Slack]
    Email[Email]
    Dashboard[Web Dashboard]
  end

  subgraph Adapters
    WebAdapter[Web Adapter]
    RepoAdapter[Repository Adapters]
    CacheAdapter[Redis Cache]
    NotifAdapter[Notification Adapters]
    QueueAdapter[Sidekiq Queue]
    DashAdapter[Dashboard Adapter]
  end

  subgraph Ports
    IngestionPort[Ingestion Port]
    StoragePort[Storage Port]
    CachePort[Cache Port]
    NotificationPort[Notification Port]
    QueuePort[Queue Port]
    DashboardPort[Dashboard Port]
  end

  subgraph Core
    domain[Domain Models]
    usecases[Use Cases]
  end

  GH --> WebAdapter
  JIRA --> WebAdapter
  BB --> WebAdapter
  WebAdapter --> IngestionPort
  
  IngestionPort --> usecases
  StoragePort --> usecases
  CachePort --> usecases
  QueuePort --> usecases
  
  usecases --> domain
  
  usecases --> NotificationPort
  usecases --> StoragePort
  usecases --> CachePort
  
  RepoAdapter --> StoragePort
  CacheAdapter --> CachePort
  NotifAdapter --> NotificationPort
  QueueAdapter --> QueuePort
  DashAdapter --> DashboardPort
  
  NotificationPort --> NotifAdapter
  DashboardPort --> DashAdapter
  
  NotifAdapter --> Slack
  NotifAdapter --> Email
  DashAdapter --> Dashboard

  classDef adapter fill:#f96,stroke:#333,stroke-width:2px
  classDef port fill:#bbf,stroke:#333,stroke-width:2px
  classDef core fill:#bfb,stroke:#333,stroke-width:2px
  classDef external fill:#eee,stroke:#333,stroke-width:1px
  
  class WebAdapter,RepoAdapter,CacheAdapter,NotifAdapter,QueueAdapter,DashAdapter adapter
  class IngestionPort,StoragePort,CachePort,NotificationPort,QueuePort,DashboardPort port
  class domain,usecases core
  class GH,JIRA,BB,Slack,Email,Dashboard external
```

### 1.2 Data Flow

```mermaid
sequenceDiagram
    participant GH as GitHub
    participant Web as WebAdapter
    participant Worker as SidekiqQueue
    participant UC as UseCase
    participant DB as Repository
    participant Cache as RedisCache
    participant Notif as SlackNotifier

    GH->>Web: Webhook Event
    Web->>Worker: Enqueue Event
    Worker->>UC: Process Event
    UC->>DB: Save Event
    UC->>UC: Calculate Metrics
    UC->>DB: Save Metrics
    UC->>Cache: Cache Metrics
    UC->>UC: Detect Anomalies
    UC->>Notif: Send Notification
```

## 2. Current Implementation 

### 2.1 Directory Layout

```
ReflexAgent/
├── app/
│   ├── core/
│   │   ├── domain/                 # Plain Ruby domain models
│   │   │   ├── classifiers/        # Event classifiers
│   │   │   ├── extractors/         # Dimension extractors
│   │   │   ├── event.rb            # Event model
│   │   │   ├── metric.rb           # Metric model
│   │   │   ├── alert.rb            # Alert model
│   │   │   ├── reflexive_agent.rb  # Agent model
│   │   │   └── ...
│   │   ├── use_cases/              # Application business logic
│   │   │   ├── calculate_metrics.rb
│   │   │   ├── detect_anomalies.rb
│   │   │   ├── process_event.rb
│   │   │   ├── send_notification.rb
│   │   │   └── ...
│   │   └── use_case_factory.rb     # Factory for instantiating use cases
│   │
│   ├── ports/                      # Interface definitions (Ruby modules)
│   │   ├── ingestion_port.rb
│   │   ├── storage_port.rb
│   │   ├── cache_port.rb
│   │   ├── notification_port.rb
│   │   ├── queue_port.rb
│   │   ├── dashboard_port.rb
│   │   ├── team_repository_port.rb
│   │   └── logger_port.rb
│   │
│   └── adapters/
│       ├── web/                    # Rails Controllers → IngestionPort
│       │   └── web_adapter.rb
│       ├── repositories/           # ActiveRecord implementations → StoragePort
│       │   ├── event_repository.rb
│       │   ├── metric_repository.rb
│       │   ├── alert_repository.rb
│       │   ├── concerns/
│       │   │   └── error_handler.rb # Shared error handling concern
│       │   ├── errors/
│       │   │   └── metric_repository_error.rb # Repository-specific errors
│       │   └── team_repository.rb
│       ├── cache/                  # Cache implementations → CachePort
│       │   ├── redis_cache.rb
│   │   │   └── event_lru_cache.rb
│       ├── notifications/          # Notification systems → NotificationPort
│       │   ├── slack_notifier.rb
│       │   └── email_notifier.rb
│       ├── queuing/                # Job queue systems → QueuePort
│       │   └── sidekiq_queue_adapter.rb
│       └── dashboard/              # UI interfaces → DashboardPort
│           └── dashboard_adapter.rb
├── config/
│   └── initializers/
│       └── dependency_injection.rb # Wiring ports to adapters
```

### 2.2 Ports and Adapters Registry

The following table shows the current port-to-adapter mapping:

| Port | Adapter(s) | Description |
|------|------------|-------------|
| **IngestionPort** | `Web::WebAdapter` | Receives events from webhooks and API endpoints |
| **StoragePort** | `Repositories::EventRepository`<br>`Repositories::MetricRepository`<br>`Repositories::AlertRepository` | Stores and retrieves domain objects |
| **CachePort** | `Cache::RedisCache` | Caches metrics and computed values |
| **NotificationPort** | `Notifications::SlackNotifier`<br>`Notifications::EmailNotifier` | Sends notifications to external systems |
| **QueuePort** | `Queuing::SidekiqQueueAdapter` | Manages background job processing |
| **DashboardPort** | `Dashboard::DashboardAdapter` | Provides data to UI components |
| **TeamRepositoryPort** | `Repositories::TeamRepository` | Manages team configurations |
| **LoggerPort** | `Rails.logger` | Provides logging capabilities |

## 3. Core Concepts

### 3.1 Domain Models

ReflexAgent's core domain models are implemented as plain Ruby objects without framework dependencies:

- **Event**: Represents an occurrence in the system that is worth tracking
- **Metric**: Represents a calculated value derived from events
- **Alert**: Represents a notification triggered when a metric crosses a threshold
- **ReflexiveAgent**: Represents an autonomous agent with perception and action capabilities

### 3.2 Ports

Ports define the contracts/interfaces that the core depends on:

```ruby
module IngestionPort
  def receive_event(raw_payload, source:)
    raise NotImplementedError
  end
  
  def validate_webhook_signature(payload, signature)
    raise NotImplementedError
  end
end
```

### 3.3 Adapters

Adapters provide concrete implementations of ports, interacting with external systems:

```ruby
module Web
  class WebAdapter
    include IngestionPort
    
    def receive_event(raw_payload, source:)
      # Implementation that converts raw webhooks into domain events
    end
  end
end
```

### 3.4 Dependency Injection

The `DependencyContainer` class wires ports to adapters at runtime:

```ruby
# In config/initializers/dependency_injection.rb
DependencyContainer.register(
  :ingestion_port,
  Web::WebAdapter.new(logger_port: logger_port)
)
```

Use cases access adapters through the container:

```ruby
# In a use case
@ingestion_port = DependencyContainer.resolve(:ingestion_port)
```

## 4. Implementation Details

### 4.1 Event Processing Pipeline

See [Event Processing Pipeline](event_processing_pipeline.md) for details.

### 4.2 Metric Calculation

See [Commit Metrics Extraction](commit_metrics_extraction.md) for details.

### 4.3 Repository Architecture

See [Repository Architecture](repository_architecture.md) for a detailed explanation of the repository layer, including:

- Repository hierarchy and types
- Error handling approach 
- Query patterns and best practices
- Usage examples

### 4.4 Dimension Standards

See [Dimension Standards](dimension_standards.md) for details.

## 5. Architecture Decisions

The following Architecture Decision Records (ADRs) document key decisions made:

- [ADR-0001](ADR/ADR-0001.md): Hexagonal Architecture Adoption
- [ADR-0002](ADR/ADR-0002.md): Event Classification Strategy
- [ADR-0003](ADR/ADR-0003-metrics-filtering-approach.md): Metrics Filtering Approach
- [ADR-0004](ADR/ADR-0004.md): Caching Strategy
- [ADR-0005](ADR/ADR-0005-metric-naming-convention.md): Metric Naming Convention
- [ADR-0006](ADR/ADR-0006-repository-error-handling.md): Repository Error Handling

## 6. Testing Strategy

### 6.1 Test Categories

- **Unit Tests**: Test individual components (domain models, extractors, use cases) in isolation
- **Integration Tests**: Test interactions between components (use cases + repositories)
- **End-to-End Tests**: Test complete flows from input to output

### 6.2 Test Structure

```
spec/
├── unit/                  # Unit tests for Core components
│   ├── core/
│   │   ├── domain/
│   │   │   ├── classifiers/
│   │   │   ├── extractors/
│   │   ├── use_cases/
├── integration/           # Integration tests
│   ├── repositories/      # Repository tests with real database
│   ├── use_cases/         # Use case tests with repositories
├── e2e/                   # End-to-end tests
│   ├── flows/             # Complete process flows
```

## 7. Developer Guides

- [Setting Up Development Environment](../guides/setup.md)
- [Working with Repositories](../guides/repositories.md)
- [Writing Use Cases](../guides/use_cases.md)
- [Testing Guidelines](../guides/testing.md)

## 8. References

- [Hexagonal Architecture](https://alistair.cockburn.us/hexagonal-architecture/)
- [Domain-Driven Design](https://martinfowler.com/bliki/DomainDrivenDesign.html)
- [SOLID Principles](https://en.wikipedia.org/wiki/SOLID)
- [Repository Pattern](https://martinfowler.com/eaaCatalog/repository.html)

---

*Last updated: June 27, 2024*

