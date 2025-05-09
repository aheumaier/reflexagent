# ReflexAgent

A monitoring and alert system using a modern Hexagonal Architecture pattern.

## System Requirements

* Ruby 3.3.2
* Rails 7.1.5
* PostgreSQL 14+
* Redis 7+
* Node.js 18+ (for asset compilation)

## Development Setup

1. Clone the repository
2. Install dependencies:
```bash
bundle install
yarn install
```
3. Set up the database:
```bash
rails db:create db:migrate db:seed
```
4. Start the development server with Foreman:
```bash
foreman start -f Procfile.dev
```

## Background Job Processing

This application uses Sidekiq for background job processing. The following queues are configured:

- `raw_events`: Processes incoming raw event data
- `event_processing`: Handles event processing tasks
- `metric_calculation`: Handles metric calculations
- `anomaly_detection`: Runs anomaly detection algorithms
- `hard_jobs`: Handles resource-intensive tasks

### Running Sidekiq

Sidekiq is included in the Procfile.dev and will start automatically with foreman. 
To run Sidekiq manually:

```bash
bundle exec sidekiq -C config/sidekiq.yml
```

### Sidekiq Dashboard

The Sidekiq web dashboard is available at `/sidekiq` in development mode.

## Testing

Run the test suite with:

```bash
bundle exec rspec
```

## Deployment

This application is configured for deployment on Render.com with the following services:

- Web service: Runs the Rails application
- Worker service: Runs Sidekiq for background processing
- PostgreSQL database
- Redis instance

The `render.yaml` file contains the full deployment configuration.

## Architecture

ReflexAgent uses a Hexagonal Architecture pattern with:

- Core domain models in `app/core/domain`
- Use cases in `app/core/use_cases`
- Ports defined in `app/ports`
- Adapters implemented in `app/adapters`

The dependency injection system wires everything together at runtime.

## Documentation

Comprehensive documentation for ReflexAgent is available in the `/docs` directory:

- [Documentation Index](docs/README.md): Central documentation hub
- [Architecture Documentation](docs/architecture/README.md): System architecture and design
- [Domain Model](docs/domain.md): Core domain concepts and models
- [Technical Details](docs/technical_depth.md): Technical implementation details
- [Testing Approach](docs/testing.md): Testing strategies and methods
- [API Documentation](docs/api/README.md): API endpoints and usage
- [User and Developer Guides](docs/guides/README.md): Step-by-step guides

For documentation standards and contribution guidelines, see the [Documentation Index](docs/README.md).
