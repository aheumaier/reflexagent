# Technical Debt Analysis - Dashboard Implementation

## Current Architecture Analysis

### Hexagonal Architecture Alignment

The current dashboard implementation has several deviations from the hexagonal architecture pattern that the application is designed to follow. The primary issues include:

1. **Missing Dashboard Adapter**: While there is a defined `DashboardPort` interface in `app/ports/dashboard_port.rb`, there is no corresponding adapter implementation. The port defines methods like `update_dashboard_with_metric` and `update_dashboard_with_alert`, but these are not being used by any adapter.

2. **Controllers Bypassing Ports**: The `DashboardsController` and `Dashboards::CommitMetricsController` directly interact with services (`MetricsService`, `DoraService`, `AlertService`) without going through the defined port interfaces. This creates a tight coupling between the UI layer and the service implementations.

3. **Direct Database Access**: There are instances in the dashboard controllers where they directly query the database (e.g., using `DomainMetric.where(...)` in `DashboardsController#pull_cicd_metrics`), bypassing the repository pattern that should encapsulate all database operations.

4. **Business Logic in Controllers**: Controllers contain significant business logic that should be encapsulated in use cases or services. For example, `DashboardsController` contains complex metric calculation and transformation logic that should be handled by the core layer.

5. **Inconsistent Use Case Integration**: While some controller methods use the use case pattern (e.g., `fetch_commit_metrics` using `UseCaseFactory.create_analyze_commits`), others directly call services or repositories.

### Service Layer Architecture Issues

The service layer itself also has architectural challenges in aligning with the hexagonal architecture pattern:

1. **Service Location Outside Core**: Services are placed in `app/services/` rather than in the core domain layer, creating confusion about their role in the architecture.

2. **Direct Repository Dependencies**: Services like `DoraService` and `MetricsService` have direct dependencies on repositories rather than ports, tightly coupling them to specific adapter implementations.

3. **Mixed Responsibilities**: Services combine both business logic and infrastructure concerns. For example, `MetricsService` handles both metric calculations (business logic) and caching (infrastructure).

4. **Inconsistent Factory Pattern**: The `ServiceFactory` introduces another layer of indirection that obscures the dependency injection pattern typically used in hexagonal architecture.

5. **Rails Dependencies in Business Logic**: Services contain Rails-specific dependencies like `Rails.logger` that should be avoided in core business logic.

### Technical Debt Areas

1. **Architectural Inconsistency**:
   - The dashboard implementation doesn't follow the hexagonal architecture pattern consistently.
   - Mixing of direct database access, service calls, and use cases creates unclear responsibility boundaries.

2. **Business Logic in UI Layer**:
   - Dashboard controllers are too complex and contain business logic that belongs in the core layer.
   - Extensive error handling and data transformation should be moved to appropriate services/use cases.

3. **Lack of Proper Dependency Injection**:
   - Controllers manually create service instances using `ServiceFactory` instead of having dependencies injected.
   - This makes testing controllers more difficult and tightly couples them to specific implementations.

4. **Duplicated Code**:
   - Similar logic for retrieving and formatting metrics is duplicated across methods in the controllers.
   - Default values and fallback logic is inconsistently applied.

5. **Inadequate Abstraction**:
   - The pattern of having extensive private methods in controllers indicates insufficient abstraction of common functionality.
   - Many of these methods should be extracted to appropriate service or use case classes.

## Recommended Refactoring Approach

### 1. Implement Dashboard Adapter

Create a proper implementation of the `DashboardPort` interface that encapsulates dashboard-related operations:

```ruby
# app/adapters/dashboard/hotwire_dashboard_adapter.rb
module Dashboard
  class HotwireDashboardAdapter
    include DashboardPort

    def initialize(metrics_service:, dora_service:, alert_service:)
      @metrics_service = metrics_service
      @dora_service = dora_service
      @alert_service = alert_service
    end

    def update_dashboard_with_metric(metric)
      # Implementation to update dashboard components via Hotwire
    end

    def update_dashboard_with_alert(alert)
      # Implementation to update dashboard alerts via Hotwire
    end

    def get_dashboard_metrics(time_period:, filters: {})
      # All the metrics aggregation logic currently in controllers
    end

    def get_commit_metrics(time_period:, repository: nil)
      # Logic from CommitMetricsController
    end
  end
end
```

### 2. Add Use Cases for Dashboard Operations

Create additional use cases that specifically handle dashboard operations:

```ruby
# app/core/use_cases/get_dashboard_metrics.rb
module UseCases
  class GetDashboardMetrics
    def initialize(storage_port:, cache_port:)
      @storage_port = storage_port
      @cache_port = cache_port
    end

    def call(time_period:, metrics_types: [], filters: {})
      # Implementation of dashboard metrics aggregation
    end
  end
end
```

### 3. Refactor Controllers

Simplify controllers to focus on HTTP concerns, delegating all business logic to the dashboard adapter or use cases:

```ruby
# app/controllers/dashboards_controller.rb (refactored)
class DashboardsController < ApplicationController
  def engineering
    @days = (params[:days] || 30).to_i
    
    # Get dashboard data through the dashboard adapter
    dashboard_adapter = DependencyContainer.resolve(:dashboard_adapter)
    @dashboard_data = dashboard_adapter.get_dashboard_metrics(
      time_period: @days,
      filters: params[:filters] || {}
    )
    
    @time_range_options = [
      ["Last 7 days", 7],
      ["Last 30 days", 30],
      ["Last 90 days", 90]
    ]
  end
end
```

### 4. Register Dashboard Adapter in Dependency Container

Update the dependency injection configuration to include the dashboard adapter:

```ruby
# In config/initializers/dependency_injection.rb
DependencyContainer.register(
  :dashboard_adapter,
  Dashboard::HotwireDashboardAdapter.new(
    metrics_service: ServiceFactory.create_metrics_service,
    dora_service: ServiceFactory.create_dora_service,
    alert_service: ServiceFactory.create_alert_service
  )
)
```

### 5. Restructure Services to Align with Hexagonal Architecture

Move business logic from services to core use cases and ensure services only handle infrastructure concerns:

```ruby
# app/core/use_cases/calculate_dora_metrics.rb
module UseCases
  class CalculateDoraMetrics
    def initialize(storage_port:, logger_port:)
      @storage_port = storage_port
      @logger_port = logger_port
    end
    
    def deployment_frequency(days = 30)
      # Implementation moved from DoraService
    end
    
    def lead_time_for_changes(days = 30)
      # Implementation moved from DoraService
    end
    
    # Other metrics methods
  end
end

# app/core/use_cases/analyze_metrics.rb
module UseCases
  class AnalyzeMetrics
    def initialize(storage_port:, cache_port:, logger_port:)
      @storage_port = storage_port
      @cache_port = cache_port
      @logger_port = logger_port
    end
    
    def time_series(metric_name, days:, interval:, unique_by: nil)
      # Implementation moved from MetricsService
    end
    
    def aggregate(metric_name, days:, aggregation:)
      # Implementation moved from MetricsService
    end
    
    # Other analysis methods
  end
end
```

Update or replace service factories with proper dependency injection:

```ruby
# Replace ServiceFactory with direct dependency injection
DependencyContainer.register(
  :dora_metrics,
  UseCases::CalculateDoraMetrics.new(
    storage_port: DependencyContainer.resolve(:metric_repository),
    logger_port: DependencyContainer.resolve(:logger_port)
  )
)

DependencyContainer.register(
  :metrics_analyzer,
  UseCases::AnalyzeMetrics.new(
    storage_port: DependencyContainer.resolve(:metric_repository),
    cache_port: DependencyContainer.resolve(:cache_port),
    logger_port: DependencyContainer.resolve(:logger_port)
  )
)
```

### 6. Improve Error Handling

Implement a consistent approach to error handling and default values:

- Move error handling from controllers to the appropriate use cases or services
- Create a standardized way to provide fallback/default metrics
- Use exceptions for exceptional cases, not for control flow

## Implementation Priority

1. **High Priority**:
   - Implement the dashboard adapter
   - Move business logic from controllers to use cases
   - Fix direct database access in controllers

2. **Medium Priority**:
   - Refactor controllers to use dependency injection
   - Improve error handling approach
   - Remove duplicated code

3. **Low Priority**:
   - Enhance caching strategy
   - Optimize database queries
   - Add comprehensive tests for dashboard components

## Conclusion

The current dashboard implementation represents a significant deviation from the hexagonal architecture pattern that the application is designed to follow. While functional, it introduces technical debt that will make the application harder to maintain, test, and extend over time.

By implementing a proper dashboard adapter, creating dedicated use cases for dashboard operations, and refactoring controllers to focus on their core responsibilities, we can bring the dashboard implementation in line with the rest of the application's architecture. 

Additionally, restructuring services to better align with hexagonal architecture principles will improve separation of concerns, testability, and maintainability across the entire application. This involves moving business logic from the service layer to core use cases and ensuring infrastructure concerns are properly encapsulated in adapters. 