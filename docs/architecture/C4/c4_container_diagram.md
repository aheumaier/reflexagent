# ReflexAgent C4 Container Diagram

This diagram shows the containers (applications, data stores, etc.) that make up the ReflexAgent system and their interactions.

## Container Diagram

```mermaid
C4Container
title Container diagram for ReflexAgent

Person(developer, "Developer", "A software developer working in a team")
Person(teamLead, "Team Lead", "Engineering manager responsible for team performance")

System_Boundary(reflexAgentSystem, "ReflexAgent System") {
    Container(webApp, "Web Application", "Ruby on Rails 7.1, Hotwire, Tailwind CSS", "Provides UI for viewing metrics and configuring the system")
    Container(apiApp, "API", "Ruby on Rails", "Provides REST API for external systems")
    Container(webhookReceiver, "Webhook Receiver", "Ruby on Rails", "Ingests events from external systems")
    Container(metricProcessor, "Metric Processor", "Ruby", "Processes events to calculate metrics")
    Container(anomalyDetector, "Anomaly Detector", "Ruby", "Detects anomalies in metrics")
    Container(notifier, "Notifier", "Ruby", "Sends notifications to users")
    Container(jobQueue, "Job Queue", "Sidekiq", "Queues background jobs")
    
    ContainerDb(database, "Database", "PostgreSQL", "Stores events, metrics, and alerts")
    ContainerDb(cacheDb, "Cache", "Redis", "Caches frequently accessed data")
    ContainerDb(vectorDb, "Vector Database", "Chroma", "Stores vector embeddings for semantic search")
}

System_Ext(github, "GitHub", "Source code and PR management")
System_Ext(jira, "Jira", "Issue tracking")
System_Ext(slack, "Slack", "Team communication")
System_Ext(email, "Email System", "Email notifications")
System_Ext(llm, "OpenAI", "LLM API")

Rel(github, webhookReceiver, "Sends webhook events", "HTTP")
Rel(jira, webhookReceiver, "Sends webhook events", "HTTP")

Rel(webhookReceiver, jobQueue, "Enqueues events for processing")
Rel(jobQueue, metricProcessor, "Processes events")
Rel(metricProcessor, database, "Stores processed metrics")
Rel(metricProcessor, anomalyDetector, "Triggers anomaly detection")
Rel(anomalyDetector, database, "Reads metrics and stores anomalies")
Rel(anomalyDetector, notifier, "Triggers notifications")
Rel(notifier, slack, "Sends notifications", "Slack API")
Rel(notifier, email, "Sends notifications", "SMTP")

Rel(developer, webApp, "Views metrics", "HTTPS")
Rel(teamLead, webApp, "Analyzes team performance", "HTTPS")
Rel(teamLead, apiApp, "Runs simulations", "HTTPS/JSON")

Rel(webApp, database, "Reads data")
Rel(webApp, cacheDb, "Caches data")
Rel(apiApp, database, "Reads/writes data")

Rel(webApp, vectorDb, "Performs semantic search")
Rel(apiApp, vectorDb, "Performs semantic search")
Rel(apiApp, llm, "Gets completions and embeddings", "OpenAI API")

UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

The container diagram shows the main components of the ReflexAgent system and how they interact with each other and external systems. The system follows a hexagonal architecture pattern with clear separation between the core domain, ports, and adapters. 