# CI/CD Setup for ReflexAgent

This document outlines the Continuous Integration and Continuous Deployment (CI/CD) configuration for the ReflexAgent application.

## Pre-commit Hooks

A pre-commit hook is set up to run RSpec tests locally before allowing a commit to proceed. This ensures that all tests pass on your local machine before you push code to the repository.

### Manual Setup

If you're setting up the project for the first time, make sure the pre-commit hook is executable:

```bash
chmod +x .git/hooks/pre-commit
```

### Skipping Pre-commit Hooks

In rare cases when you need to bypass the pre-commit hook (not recommended for normal workflow):

```bash
git commit -m "Your message" --no-verify
```

## GitHub Actions Workflows

### CI Workflow

The CI workflow runs on every push to the `main` branch and on every pull request targeting the `main` branch. It performs the following tasks:

1. Sets up the test environment with PostgreSQL and Redis
2. Installs dependencies
3. Prepares the test database
4. Runs unit tests
5. Runs integration tests
6. Generates a test coverage report

### Deployment Workflow

The deployment workflow is triggered on pushes to the `main` branch or manually through the GitHub Actions interface. It:

1. Runs all tests to ensure the build is deployable
2. Deploys the application to Render
3. Configures GitHub webhooks to send events to the deployed application

## Self-Monitoring Architecture (Dogfooding)

The ReflexAgent application is configured to monitor itself by consuming its own GitHub events. This self-monitoring setup provides several benefits:

1. **Eating our own dog food**: We use our own product to validate its quality
2. **Real-world testing**: The application processes real events from its own repository
3. **Performance insights**: We can monitor how the system handles its own development activities
4. **Immediate feedback**: Issues with event processing are quickly discovered

The setup works as follows:

1. The GitHub Actions deployment workflow configures a webhook from the ReflexAgent repository to the deployed application
2. Events from the repository (commits, pull requests, issues, comments) are sent to the `/api/v1/events?source=github` endpoint
3. The application processes these events through its hexagonal architecture
4. Metrics are calculated, anomalies are detected, and alerts are sent based on the repository's activity

## Secrets Configuration

For the deployment workflow to function correctly, the following secrets must be configured in your GitHub repository:

- `RENDER_API_KEY`: Your Render API key
- `RENDER_SERVICE_ID`: The ID of your web service in Render
- `RENDER_WEBHOOK_URL`: The URL of your deployed application (e.g., `https://reflexagent-web.onrender.com`)
- `WEBHOOK_SECRET`: A secret token for GitHub webhook verification
- `GH_PAT_TOKEN`: A GitHub Personal Access Token with repo and admin:repo_hook permissions
- `RAILS_MASTER_KEY`: Your Rails master key for credentials encryption

To add these secrets:

1. Go to your GitHub repository
2. Navigate to Settings > Secrets and variables > Actions
3. Click "New repository secret" to add each secret

## Local CI Testing

To test the CI pipeline locally before pushing:

```bash
# Run the same tests that CI will run
bundle exec rspec
```

## Deployment Configuration

The application deployment is configured in the `render.yaml` Blueprint file, which defines:

1. **Web Service**: The main Rails application
2. **Worker Service**: The Sidekiq background job processor
3. **PostgreSQL Database**: For persistent storage
4. **Redis Instance**: For caching and job queuing

## Render as a Deployment Target

Render was chosen as the deployment target for these reasons:

1. **Modern PaaS**: Purpose-built for modern web applications
2. **Native Blueprint Support**: Infrastructure as code with `render.yaml`
3. **Managed PostgreSQL and Redis**: Easy setup of required services
4. **Automatic HTTPS**: SSL certificates and custom domains
5. **Multiple Service Types**: Support for web services and background workers
6. **Competitive Pricing**: More cost-effective than Heroku for similar features
7. **GitHub Integration**: Easy deployment from GitHub repositories 