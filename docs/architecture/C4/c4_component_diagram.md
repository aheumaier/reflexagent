# ReflexAgent C4 Component Diagram

This diagram illustrates the key components of the ReflexAgent system, focusing on the hexagonal architecture implementation.

## Component Diagram

```mermaid
C4Component
title Component diagram for ReflexAgent (Hexagonal Architecture)

Container_Boundary(webApp, "Web Application") {
    Component(dashboardController, "Dashboard Controller", "Rails Controller", "Provides dashboard UI")
    Component(dashboardAdapter, "Dashboard Adapter", "Adapter", "Implements dashboard port")
}

Container_Boundary(apiApp, "API") {
    Component(apiController, "API Controller", "Rails Controller", "Provides REST API endpoints")
    Component(webAdapter, "Web Adapter", "Adapter", "Implements web port")
}

Container_Boundary(webhookReceiver, "Webhook Receiver") {
    Component(webhookController, "Webhook Controller", "Rails Controller", "Receives webhook events")
    Component(ingestionAdapter, "Ingestion Adapter", "Adapter", "Implements ingestion port")
}

Container_Boundary(core, "Core Domain") {
    Component(domainModels, "Domain Models", "Ruby Classes", "Event, Metric, Alert, etc.")
    
    Component_Boundary(useCases, "Use Cases") {
        Component(processEvent, "Process Event", "Use Case", "Processes raw events")
        Component(calculateMetrics, "Calculate Metrics", "Use Case", "Calculates metrics from events")
        Component(detectAnomalies, "Detect Anomalies", "Use Case", "Detects anomalies in metrics")
        Component(sendNotification, "Send Notification", "Use Case", "Sends notifications")
        Component(dashboardMetrics, "Dashboard Metrics", "Use Case", "Gets metrics for dashboard")
    }
    
    Component_Boundary(ports, "Ports") {
        Component(ingestionPort, "Ingestion Port", "Interface", "Event ingestion interface")
        Component(storagePort, "Storage Port", "Interface", "Data storage interface")
        Component(cachePort, "Cache Port", "Interface", "Data caching interface")
        Component(queuePort, "Queue Port", "Interface", "Job queuing interface")
        Component(notificationPort, "Notification Port", "Interface", "Notification interface")
        Component(dashboardPort, "Dashboard Port", "Interface", "Dashboard interface")
    }
}

Container_Boundary(adapters, "Adapters") {
    Component(eventRepository, "Event Repository", "Repository", "Implements storage port for events")
    Component(metricRepository, "Metric Repository", "Repository", "Implements storage port for metrics")
    Component(alertRepository, "Alert Repository", "Repository", "Implements storage port for alerts")
    Component(redisCache, "Redis Cache", "Adapter", "Implements cache port")
    Component(sidekiqQueue, "Sidekiq Queue", "Adapter", "Implements queue port")
    Component(slackNotifier, "Slack Notifier", "Adapter", "Implements notification port for Slack")
    Component(emailNotifier, "Email Notifier", "Adapter", "Implements notification port for email")
    Component(chromaClient, "Chroma Client", "Adapter", "Implements vector DB port")
}

ContainerDb(database, "Database", "PostgreSQL", "Stores events, metrics, and alerts")
ContainerDb(cacheDb, "Cache", "Redis", "Caches frequently accessed data")
ContainerDb(vectorDb, "Vector Database", "Chroma", "Stores vector embeddings")
Container(jobQueue, "Job Queue", "Sidekiq", "Queues background jobs")

Rel(webhookController, ingestionAdapter, "Uses")
Rel(ingestionAdapter, ingestionPort, "Implements")
Rel(ingestionPort, processEvent, "Used by")

Rel(dashboardController, dashboardAdapter, "Uses")
Rel(dashboardAdapter, dashboardPort, "Implements")
Rel(dashboardPort, dashboardMetrics, "Used by")

Rel(apiController, webAdapter, "Uses")
Rel(webAdapter, dashboardPort, "Implements")

Rel(processEvent, calculateMetrics, "Triggers")
Rel(calculateMetrics, detectAnomalies, "Triggers")
Rel(detectAnomalies, sendNotification, "Triggers")

Rel(processEvent, storagePort, "Uses")
Rel(calculateMetrics, storagePort, "Uses")
Rel(detectAnomalies, storagePort, "Uses")
Rel(dashboardMetrics, storagePort, "Uses")
Rel(dashboardMetrics, cachePort, "Uses")
Rel(sendNotification, notificationPort, "Uses")
Rel(processEvent, queuePort, "Uses")

Rel(storagePort, eventRepository, "Implemented by")
Rel(storagePort, metricRepository, "Implemented by")
Rel(storagePort, alertRepository, "Implemented by")
Rel(cachePort, redisCache, "Implemented by")
Rel(queuePort, sidekiqQueue, "Implemented by")
Rel(notificationPort, slackNotifier, "Implemented by")
Rel(notificationPort, emailNotifier, "Implemented by")

Rel(eventRepository, database, "Uses")
Rel(metricRepository, database, "Uses")
Rel(alertRepository, database, "Uses")
Rel(redisCache, cacheDb, "Uses")
Rel(sidekiqQueue, jobQueue, "Uses")
Rel(chromaClient, vectorDb, "Uses")

UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

This component diagram illustrates the hexagonal architecture of ReflexAgent with:

1. **Core Domain**: Contains the business logic (domain models and use cases)
2. **Ports**: Defines interfaces for external systems
3. **Adapters**: Implements the ports to connect with external systems
4. **External Systems**: Database, cache, job queue, etc.

The design ensures that the core domain doesn't depend on external systems, making it easy to test, maintain, and evolve. 