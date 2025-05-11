# Repository Layer Component Diagram

This diagram shows the component structure of the repository layer in ReflexAgent.

## Repository Components Diagram

```mermaid
C4Component
title Repository Layer Component Diagram

Enterprise_Boundary(b0, "ReflexAgent") {
  Container_Boundary(c1, "Core") {
    Component(useCases, "Use Cases", "Ruby", "Core business logic that implements application functionality")
  }
  
  Container_Boundary(c2, "Ports") {
    Component(storagePort, "Storage Port", "Ruby Module", "Interface defining persistence operations")
    Component(loggerPort, "Logger Port", "Ruby Module", "Interface defining logging operations")
  }
  
  Container_Boundary(c3, "Repository Layer") {
    Component(repoFactory, "Metric Repository Factory", "Ruby Class", "Creates appropriate repository instances based on metric type")
    
    Component(baseRepo, "Base Metric Repository", "Ruby Class", "Provides common functionality for all metric repositories")
    Component(gitRepo, "Git Metric Repository", "Ruby Class", "Specializes in Git-related metrics")
    Component(doraRepo, "DORA Metrics Repository", "Ruby Class", "Specializes in DORA-specific metrics")
    Component(issueRepo, "Issue Metric Repository", "Ruby Class", "Specializes in issue-related metrics")
    Component(eventRepo, "Event Repository", "Ruby Class", "Manages event persistence")
    Component(teamRepo, "Team Repository", "Ruby Class", "Manages team configurations")
    Component(alertRepo, "Alert Repository", "Ruby Class", "Manages alert persistence")
    
    Container_Boundary(c4, "Shared Components") {
      Component(errorHandler, "Error Handler", "Ruby Module", "Standardizes error handling across repositories")
      Component(errorTypes, "Repository Errors", "Ruby Classes", "Hierarchy of domain-specific repository errors")
    }
  }
  
  Container_Boundary(c5, "Infrastructure") {
    Component(activeRecord, "Active Record Models", "Ruby Classes", "ORM models mapping to database tables")
    Component(railsLogger, "Rails Logger", "Ruby Object", "Logging implementation")
  }
  
  Rel(useCases, storagePort, "Uses", "Depends on interface")
  Rel(useCases, loggerPort, "Uses", "Depends on interface")
  
  Rel(storagePort, repoFactory, "Implemented by", "Factory produces objects implementing port")
  Rel(loggerPort, railsLogger, "Implemented by", "Concrete implementation")
  
  Rel(repoFactory, baseRepo, "Creates", "Factory method")
  Rel(repoFactory, gitRepo, "Creates", "Factory method")
  Rel(repoFactory, doraRepo, "Creates", "Factory method")
  Rel(repoFactory, issueRepo, "Creates", "Factory method")
  
  Rel(baseRepo, errorHandler, "Includes", "Mixin")
  Rel(baseRepo, activeRecord, "Uses", "For data access")
  Rel(baseRepo, railsLogger, "Uses", "For logging")
  
  Rel(gitRepo, baseRepo, "Inherits from", "Extends")
  Rel(doraRepo, baseRepo, "Inherits from", "Extends")
  Rel(issueRepo, baseRepo, "Inherits from", "Extends")
  
  Rel(errorHandler, errorTypes, "Raises", "When errors occur")
  Rel(errorHandler, loggerPort, "Uses", "For error logging")
}
```

## Repository Error Hierarchy Diagram

```mermaid
classDiagram
    StandardError <|-- MetricRepositoryError
    MetricRepositoryError <|-- DatabaseError
    MetricRepositoryError <|-- ValidationError
    MetricRepositoryError <|-- QueryError
    MetricRepositoryError <|-- NotFoundError
    MetricRepositoryError <|-- UnsupportedOperationError
    ValidationError <|-- InvalidMetricNameError
    ValidationError <|-- InvalidDimensionError
    
    class StandardError {
        +message
        +backtrace
    }
    
    class MetricRepositoryError {
        +String message
        +Hash context
        +Exception cause
        +initialize(message, context, cause)
        +to_s()
    }
    
    class DatabaseError {
        +String operation
        +initialize(operation, cause, context)
    }
    
    class ValidationError {
        +initialize(message, context)
    }
    
    class QueryError {
        +String query_type
        +initialize(query_type, cause, context)
    }
    
    class NotFoundError {
        +String id
        +initialize(id, cause, context)
    }
    
    class UnsupportedOperationError {
        +String operation
        +initialize(operation, context)
    }
    
    class InvalidMetricNameError {
        +String name
        +initialize(name, context)
    }
    
    class InvalidDimensionError {
        +String dimension_name
        +String dimension_value
        +initialize(name, value, context)
    }
```

## Repository Method Flow Diagram

```mermaid
sequenceDiagram
    participant UC as UseCase
    participant RF as RepositoryFactory
    participant GR as GitMetricRepository
    participant BR as BaseMetricRepository
    participant EH as ErrorHandler
    participant AR as ActiveRecord
    participant DB as Database
    participant LP as LoggerPort
    
    UC->>RF: create_repository(:git)
    RF->>GR: new(logger_port: logger)
    GR->>BR: super(logger_port: logger)
    
    Note over UC,LP: Repository Operation Flow
    
    UC->>GR: get_time_to_merge_for_repository("acme/repo")
    GR->>GR: context = { repo: "acme/repo" }
    GR->>EH: handle_database_error("get_time_to_merge", context)
    EH->>AR: query for metrics
    AR->>DB: SQL query
    DB->>AR: result set
    
    alt Success Path
        AR->>EH: result
        EH->>GR: result
        GR->>UC: processed result
    else Error Path
        AR->>EH: raise ActiveRecord::Error
        EH->>LP: log_error("Database error: ...")
        EH->>EH: raise DatabaseError
        EH->>GR: propagate error
        GR->>UC: propagate error
    end
``` 