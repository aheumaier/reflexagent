# ReflexAgent C4 Context Diagram

This diagram illustrates the high-level system context of the ReflexAgent application, showing how it interacts with external systems and users.

## Context Diagram

```mermaid
C4Context
title System Context diagram for ReflexAgent

Person(developer, "Developer", "A software developer working in a team")
Person(teamLead, "Team Lead", "Engineering manager responsible for team performance")

System(reflexAgent, "ReflexAgent", "AI-augmented Digital Agent that processes development data, detects anomalies, and provides insights")

System_Ext(github, "GitHub", "Source code and pull request management platform")
System_Ext(jira, "Jira", "Issue and project tracking system")
System_Ext(slack, "Slack", "Team communication platform")
System_Ext(email, "Email System", "Email notifications")
System_Ext(llm, "OpenAI", "Large Language Model API for AI capabilities")

Rel(github, reflexAgent, "Sends webhook events", "GitHub API")
Rel(jira, reflexAgent, "Sends webhook events", "Jira API")

Rel(reflexAgent, slack, "Sends notifications and insights", "Slack API")
Rel(reflexAgent, email, "Sends notifications", "SMTP")
Rel(reflexAgent, llm, "Requests completions and embeddings", "OpenAI API")

Rel(developer, reflexAgent, "Views metrics and receives suggestions")
Rel(teamLead, reflexAgent, "Analyzes team performance and simulates scenarios")

UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

The context diagram shows how ReflexAgent sits at the center of the engineering ecosystem, ingesting data from development tools (GitHub, Jira), processing it with AI assistance (OpenAI), and providing insights to team members through various channels (Dashboard, Slack, Email). 