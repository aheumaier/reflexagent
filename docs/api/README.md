# ReflexAgent API Documentation

This directory contains documentation for the ReflexAgent API endpoints and integrations.

> **Navigation**: [Documentation Index](../README.md) | [Webhooks](../webhooks/README.md) | [Technical Documentation](../technical/README.md) | [Domain Model](../domain/README.md)

## API Overview

ReflexAgent provides the following types of APIs:

1. **RESTful API**: For dashboard data, configuration, and metrics retrieval
2. **Webhook Receivers**: For ingesting events from external systems
3. **Notification Endpoints**: For sending alerts and notifications

## API Documentation Structure

The API documentation is organized as follows:

```
api/
├── README.md             # This file - API documentation overview
├── rest/                 # RESTful API documentation
│   ├── metrics.md        # Metrics API endpoints
│   ├── teams.md          # Teams API endpoints
│   └── alerts.md         # Alerts API endpoints
├── webhooks/             # Webhook API documentation
│   ├── github.md         # GitHub webhook integration
│   └── jira.md           # Jira webhook integration
└── integrations/         # Third-party integration documentation
    ├── slack.md          # Slack integration API
    └── email.md          # Email notification API
```

## Authentication

All ReflexAgent API endpoints use token-based authentication. Include your API token in the `Authorization` header:

```
Authorization: Bearer YOUR_API_TOKEN
```

## Rate Limiting

API rate limits are set to:
- 100 requests per minute for regular endpoints
- 1000 requests per minute for webhook receivers

## API Documentation Template

When documenting API endpoints, please use the following format:

```markdown
# API: [Endpoint Name]

## Overview
Brief description of the endpoint's purpose

## Endpoint
`METHOD /path/to/endpoint`

## Authentication
Required authentication method

## Request Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| param1    | type | yes/no   | description |

## Request Body
Example JSON request body with description

## Response
Example JSON response with description

## Status Codes
| Code | Description |
|------|-------------|
| 200  | Success     |
| 400  | Bad Request |

## Examples
### Example Request
```curl
curl -X POST https://api.example.com/endpoint \
  -H "Authorization: Bearer token" \
  -d '{"param": "value"}'
```

### Example Response
```json
{
  "result": "success"
}
```

## Error Handling
Common errors and troubleshooting
```

## Related Documentation

- [Webhooks Documentation](../webhooks/README.md) - How to configure and use webhooks
- [GitHub Webhook Setup](../webhooks/github_setup.md) - Detailed GitHub webhook configuration
- [Event Processing Pipeline](../architecture/event_processing_pipeline.md) - How API requests are processed
- [Domain Model](../domain/README.md) - Core domain concepts 
- [Technical Debt - API Section](../technical/debt_analysis.md#documentation-shortcomings) - Known API documentation issues

---

*Last updated: June 27, 2024* 