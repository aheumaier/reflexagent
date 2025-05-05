# ReflexAgent AI Onboarding

## 1. Code Patterns & Conventions  
- We use **Hotwire** for reactivity, never direct WebSockets.  
- All service-objects live under `app/core/use_cases/…`.  
- We favor small, well-named methods over comments.  
- Database calls only in repository adapters (`app/adapters/repositories/…`).  

## 2. Tech Stack & Tooling  
- Ruby 3.3.2 (2024-05-30 revision e5a195edf6) [arm64-darwin23] 
- Rails 7.1.5.1, 
- Postgres
-  Redis, 
- Sidekiq  
- TailwindCSS for styles
- Stimulus for JS  
- Cursor snippets in `/.cursor/prompts/`  

## 3. Running the Suite  
- Unit tests: `bundle exec rspec`  
- DB setup: `bin/rails db:prepare`  
- Demo events: `ruby lib/demo_events.rb`  

## 4. Available Helpers  
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
