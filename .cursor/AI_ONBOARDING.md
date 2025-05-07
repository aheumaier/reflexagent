# ReflexAgent AI Onboarding
## 1. Project Purpose

ReflexAgent is a **Hexagonal-architecture** Rails 7.1 application that implements a data-driven, AI-augmented "Digital Agent" for engineering teams. It:

* Ingests and normalizes events (GitHub, Jira, etc.)
* Computes team health metrics (cycle time, PR-review time)
* Detects anomalies and issues empathetic nudges via Slack/email
* Supports advanced AI-driven simulations and recommendations via a reflexive agent model
* Leverages a vector DB (Chroma) and LLM (OpenAI) for retrieval-augmented intelligence

This aligns with Jurgen Appelo’s **Human Robot Agent** vision: augment human teams with unbiased, data-driven, context-aware AI support.

## 2. Key Use Cases & Flows

1. **Anomaly Detection & Nudge**

   * Continuously compute rolling metrics → detect spikes → send a non-judgmental Slack suggestion.
2. **What-If Simulations**

   * Simulate adding team members or adjusting scope → predict delivery impact.
3. **Reflective Q\&A**

   * Surface contextual questions in retrospectives based on detected patterns or alerts.
4. **Predictive Risk Alerts**

   * Forecast scope creep or backlog issues during sprint planning.
5. **Similarity-Based Retrieval**

   * New team member queries → retrieve past incident summaries from Chroma.

## 3. Roadmap (1-Month POC)

1. **Bootstrapping & Core Skeleton**

   * Rails project setup, hexagonal directory structure, DI wiring.
2. **Domain Models & Use Cases**

   * Implement plain Ruby `Event`, `Metric`, `Alert`, `ReflexiveAgent` + `ProcessEvent`, `CalculateMetrics`, `DetectAnomalies`, `SendNotification`.
3. **Ports & Adapters**

   * Define ports under `app/ports`, stub adapters under `app/adapters`.
4. **Ingestion → Queue → Metrics**

   * Webhooks controller, Sidekiq job, metrics calculation, caching.
5. **Anomaly Detection & Notification**

   * Threshold logic, Slack/email notifier adapter.
6. **Dashboard & Deploy**

   * Hotwire/Tailwind UI, Render.com config.
7. **Chroma & LLM Integration**

   * Embeddings seeding, retrieval-augmented prompts, Model Context Protocol.

## 4. Project Structure & Docs

* **app/core/**: Domain models and use case classes (pure Ruby)
* **app/ports/**: Interface definitions (Ingestion, Storage, Cache, Queue, Notification, Dashboard, Embeddings)
* **app/adapters/**: Concrete implementations (Rails controllers, ActiveRecord repos, Redis cache, Sidekiq queue, Slack/email notifier, Chroma client)
* **docs/architecture/**: ADRs, domain overviews, pipeline docs
* **lib/demo\_events.rb**: Script to simulate events
* **spec/**: RSpec tests for core and adapters

### Important Docs to Read

* `docs/architecture/README.md` (architecture overview)
* `docs/architecture/ADR-0001.md`..`ADR-0004.md` (decision records)
* `docs/architecture/domain_model.md` (detailed domain logic)
* `docs/architecture/event_processing_pipeline.md` (event/matric pipeline)

## 5. AI Agent Guidelines

* **Use Model Context Protocol**: Inject system, long-term memory (Chroma), short-term memory (Redis/Postgres), tool schemas, and user query.
* **Tool Registry**: Available tools are defined by ports/adapters. Use function-calling spec for `get_metrics`, `query_chroma`, `enqueue_job`, etc.
* **Chain-of-Vibes Workflow**: Break tasks into plan (5–7 steps), then step-by-step execution with small commits.
* **Refresh Context**: Reload AI onboarding doc and relevant code artifacts at each step to avoid stale context.

## 6. Code Patterns & Conventions  
- We use **Hotwire** for reactivity, never direct WebSockets.  
- All service-objects live under `app/core/use_cases/…`.  
- We favor small, well-named methods over comments.  
- Database calls only in repository adapters (`app/adapters/repositories/…`).  

## 7. Tech Stack & Tooling  
- Ruby 3.3.2 (2024-05-30 revision e5a195edf6) [arm64-darwin23] 
- Rails 7.1.5.1, 
- Postgres
-  Redis, 
- Sidekiq  
- TailwindCSS for styles
- Stimulus for JS  
- Cursor snippets in `/.cursor/prompts/`  

## 8. Running the Suite  
- Unit tests: `bundle exec rspec`  
- DB setup: `bin/rails db:prepare`  
- Demo events: `ruby docs/demo_events.rb`  

## 9. Available Helpers  
- `VibePlan:` Prompt template for implementation plans  
- `VibeStep:` Prompt template for single-step coding  
- `Clarify:` Prompt template to ask questions  

## 5. Project Structure
ReflexAgent/
├── app/
│   ├── core/
│   │   ├── domain/
│   │   │   ├── classifiers/
│   │   │   │   ├── github_event_classifier.rb
│   │   │   │   ├── metric_classifier.rb
│   │   │   │   └── ...
│   │   │   ├── extractors/
│   │   │   │   └── dimension_extractor.rb
│   │   │   ├── event.rb
│   │   │   ├── metric.rb
│   │   │   └── alert.rb
│   │   └── use_cases/
│   │       ├── process_event.rb
│   │       ├── calculate_metrics.rb
│   │       ├── detect_anomalies.rb
│   │       ├── analyze_commits.rb
│   │       ├── dashboard_metrics.rb
│   │       ├── find_event.rb
│   │       ├── find_metric.rb
│   │       ├── list_metrics.rb
│   │       └── send_notification.rb
│   │
│   ├── ports/
│   │   ├── ingestion_port.rb
│   │   ├── storage_port.rb
│   │   ├── cache_port.rb
│   │   ├── notification_port.rb
│   │   ├── queue_port.rb
│   │   └── dashboard_port.rb
│   │
│   ├── adapters/
│   │   ├── web/
│   │   │   ├── webhooks_controller.rb
│   │   │   ├── web_adapter.rb
│   │   │   └── ...
│   │   │
│   │   ├── repositories/
│   │   │   ├── event_repository.rb
│   │   │   ├── metric_repository.rb
│   │   │   └── alert_repository.rb
│   │   │
│   │   ├── cache/
│   │   │   └── redis_cache.rb
│   │   │
│   │   ├── notifications/
│   │   │   └── slack_notifier.rb
│   │   │
│   │   └── queuing/
│   │       └── ...
│   │
│   ├── controllers/
│   │   ├── api/
│   │   │   └── v1/
│   │   └── dashboards/
│   │
│   ├── models/
│   │   ├── domain_event.rb
│   │   ├── domain_metric.rb
│   │   └── ...
│   │
│   ├── views/
│   │   ├── dashboards/
│   │   │   ├── commit_metrics/
│   │   │   └── partials/
│   │   └── ...
│   │
│   └── sidekiq/
│       ├── raw_event_job.rb
│       ├── metric_calculation_job.rb
│       └── metric_aggregation_job.rb
│
├── config/
│   ├── initializers/
│   │   └── dependency_injection.rb
│   └── ...
│
├── db/
│   └── migrate/
│
├── docs/
│   ├── architecture/
│   │   ├── README.md
│   │   ├── domain_model.md
│   │   ├── commit_metrics_extraction.md
│   │   └── ADR-000*.md
│   └── webhooks/
│       └── github_setup.md
│
├── lib/
│   └── demo_events.rb      # Script for simulating webhook events
│
├── spec/
│   ├── core/
│   │   ├── domain/
│   │   │   ├── extractors/
│   │   │   └── classifiers/
│   │   └── use_cases/
│   ├── adapters/
│   │   ├── repositories/
│   │   ├── web/
│   │   └── ...
│   ├── support/
│   │   ├── shared_contexts/
│   │   └── ...
│   └── ...
│
└── ...


## 6. Architecture Documentation
- Architecture Documentation(ADRs) `docs/architecture/`
- docs/architecture/README.md
- docs/architecture/domain_model.md
- docs/architecture/commit_metrics_extraction.md
- docs/architecture/ADR-0001.md
- docs/architecture/ADR-0002.md
