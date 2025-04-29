# Architecture Documentation for ReflexAgent

This document provides an overview of the planned Hexagonal (Ports & Adapters) architecture for ReflexAgent, guiding developers through the core concepts, directory layout, and key guidelines.

## 1. Architectural Overview

ReflexAgent is organized following the Hexagonal/Ports & Adapters pattern to achieve:

- **Separation of Concerns**: Business logic (core) is isolated from frameworks and infrastructure.
- **Testability**: Core use cases and domain models are framework-agnostic and can be unit tested with mock ports.
- **Replaceability**: Infrastructure components (Rails, Redis, Sidekiq, Slack, Python services) can be swapped by implementing different adapters without touching core logic.

```mermaid
flowchart LR
  subgraph Core (app/core)
    UC1[ProcessEvent]
    UC2[CalculateMetrics]
    UC3[DetectAnomalies]
    UC4[SendNotification]
    D[Domain Models: Event, Metric, Alert]
  end

  subgraph Ports (app/ports)
    P1[IngestionPort]
    P2[StoragePort]
    P3[CachePort]
    P4[NotificationPort]
    P5[QueuePort]
    P6[DashboardPort]
  end

  subgraph Adapters (app/adapters)
    A1[WebAdapter (Rails Controllers)]
    A2[EventRepository (ActiveRecord)]
    A3[RedisCache]
    A4[SlackNotifier]
    A5[ProcessEventWorker (Sidekiq)]
    A6[UiAdapter (Hotwire/Stimulus)]
  end

  A1 --> P1
  P1 --> UC1
  UC1 --> P5
  A5 --> UC2
  UC2 --> P2
  UC2 --> P3
  UC2 --> UC3
  UC3 --> P4
  P4 --> A4
  A6 --> P6
  P6 --> UC2
  P6 --> UC4

  UC4 --> P4
```  

## 2. Directory Layout

```
ReflexAgent/
├── app/
│   ├── core/
│   │   ├── domain/             # Plain Ruby domain models
│   │   └── use_cases/          # Application business logic
│   ├── ports/                  # Interface definitions (Ruby modules)
│   └── adapters/
│       ├── web/                # Rails Controllers → IngestionPort
│       ├── repositories/       # ActiveRecord implementations → StoragePort
│       ├── cache/              # RedisCache → CachePort
│       ├── notifications/      # SlackNotifier → NotificationPort
│       └── queue/              # Sidekiq workers → QueuePort
├── config/
│   └── initializers/
│       └── dependency_injection.rb  # Wiring ports to adapters
└── docs/
    └── architecture/
        ├── ADR-0001-use-hexagonal-architecture.md
        ├── ADR-0002-rails-as-host-platform-vs-api-only-react.md
        └── README.md          # This document
```

## 3. Core Concepts

- **Core (Domain & Use Cases)**: Contains business rules and orchestrations in `app/core/`. No external dependencies.
- **Ports**: Define the contracts/interfaces that the core depends on. Located in `app/ports/`.
- **Adapters**: Concrete implementations of ports. Located in `app/adapters/` and interact with external systems.
- **Dependency Injection**: Initialized in `config/initializers/dependency_injection.rb`, mapping each port to its adapter.

## 4. Getting Started

1. **Review ADRs**: Understand the rationale behind major architectural decisions by reading ADR-0001 and ADR-0002.
2. **Explore Core**: Start with `app/core/domain` and `app/core/use_cases` to see business logic.
3. **Inspect Ports**: Look at `app/ports` to view interface definitions.
4. **Check Adapters**: Examine each adapter under `app/adapters` to see how ports are implemented.
5. **Dependency Wiring**: Open `config/initializers/dependency_injection.rb` to verify which adapters are bound to which ports.

## 5. Guidelines & Best Practices

- **No Framework Code in Core**: Avoid importing Rails, ActiveRecord, or other libs in `app/core/`.
- **Keep Ports Lean**: Only method signatures; no logic.
- **Adapters as Thin Wrappers**: Each adapter should adapt the external API to the port interface.
- **Unit Tests for Core**: Use port mocks to test use cases without hitting DB or external services.
- **Integration Tests for Adapters**: Test each adapter against a real (or test) instance of its external system.

---

*Last updated: 2025-04-30*

