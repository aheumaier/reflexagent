# Unified Webhook API

ReflexAgent provides a unified webhook endpoint that accepts events from various sources like GitHub, Jira, GitLab, and more.

## Endpoint

```
POST /api/v1/events?source=SOURCE_TYPE
```

## Authentication

The API supports two authentication methods:

1. **X-Webhook-Token Header**:
   ```
   X-Webhook-Token: your_secret_token
   ```

2. **Bearer Token**:
   ```
   Authorization: Bearer your_secret_token
   ```

## Request Format

### Headers
- `Content-Type: application/json` (required)
- `X-Webhook-Token: your_secret_token` or `Authorization: Bearer your_secret_token` (required)

### Query Parameters
- `source`: Indicates the webhook source (required)
  - Supported values: `github`, `jira`, `gitlab`, `bitbucket`, etc.

### Body
- Send the raw JSON payload from the source system as-is.
- No need to transform the payload before sending it.

## Example Requests

### GitHub Webhook

```bash
curl -X POST "https://your-reflexagent.com/api/v1/events?source=github" \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Token: your_secret_token" \
  -d '{
    "action": "opened",
    "pull_request": {
      "id": 123456,
      "title": "Fix bug in metrics calculation",
      "user": {
        "login": "developer1"
      }
    },
    "repository": {
      "full_name": "organization/repo"
    }
  }'
```

### Jira Webhook

```bash
curl -X POST "https://your-reflexagent.com/api/v1/events?source=jira" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your_secret_token" \
  -d '{
    "webhookEvent": "jira:issue_updated",
    "issue": {
      "key": "PROJECT-123",
      "fields": {
        "summary": "Improve error handling",
        "status": {
          "name": "In Progress"
        }
      }
    }
  }'
```

## Response Format

### Success Response

```json
{
  "id": "event-uuid",
  "status": "processed",
  "source": "github"
}
```

Status code: 201 Created

### Error Responses

**Bad Request (400)**
```json
{
  "error": "source is missing"
}
```

**Bad Request (400) - Invalid JSON**
```json
{
  "error": "Invalid JSON payload: unexpected token at line 2"
}
```

**Unauthorized (401)**
```
(No body)
```

**Unprocessable Entity (422)**
```json
{
  "error": "Error processing event: Invalid event type"
}
```

## Configuring Source Webhooks

### GitHub

1. Go to your GitHub repository
2. Navigate to Settings > Webhooks > Add webhook
3. Set Payload URL to `https://your-reflexagent.com/api/v1/events?source=github`
4. Set Content type to `application/json`
5. Set Secret to your webhook token
6. Choose which events to trigger the webhook

### Jira

1. Go to Jira Settings > System > WebHooks > Create a WebHook
2. Set URL to `https://your-reflexagent.com/api/v1/events?source=jira`
3. Add a custom HTTP header: `X-Webhook-Token: your_secret_token`
4. Select the events you want to receive

## Event Processing

When a webhook is received:

1. The payload is validated and authenticated
2. An internal domain event is created
3. The event is stored in the database
4. The event is scheduled for asynchronous processing
5. Metrics are calculated based on the event
6. Anomalies are detected and alerts are raised if needed 