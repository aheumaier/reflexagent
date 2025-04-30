# Setting Up GitHub Webhooks

This document outlines how to configure GitHub webhooks to send events to ReflexAgent.

## Overview

ReflexAgent can receive and process GitHub webhook events, including:
- Commits (push events)
- Pull Requests (opening, closing, merging)
- Pull Request Reviews

## Prerequisites

1. A GitHub repository you want to monitor
2. Administrative access to that repository
3. A publicly accessible URL for your ReflexAgent instance

## Webhook Configuration in GitHub

1. Go to your GitHub repository
2. Click on "Settings" > "Webhooks" > "Add webhook"
3. Configure the webhook:
   - **Payload URL**: `https://your-reflexagent-domain.com/api/v1/events/github`
   - **Content type**: `application/json`
   - **Secret**: Generate a strong, unique secret (see below)
   - **Which events would you like to trigger this webhook?**: 
     - For all events: "Send me everything"
     - For specific events: "Let me select individual events" and choose:
       - Push
       - Pull requests
       - Pull request reviews

## Webhook Secret Management

### Generating a Secure Webhook Secret

Generate a strong, random secret with:

```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(20)'
```

### Configuring the Secret in ReflexAgent

1. Add the secret to your Rails credentials:

```bash
rails credentials:edit
```

2. Add the GitHub webhook secret:

```yaml
github:
  webhook_secret: your_generated_secret_here
```

## Security Best Practices

1. **Always use HTTPS**: Webhook payloads contain sensitive information
2. **Validate signatures**: ReflexAgent automatically validates the `X-Hub-Signature-256` header
3. **Restrict IP addresses**: Consider restricting incoming webhook requests to [GitHub's IP ranges](https://api.github.com/meta)
4. **Implement rate limiting**: To prevent abuse
5. **Monitor for failures**: Check logs regularly for signature validation failures

## Troubleshooting

### Common Issues

1. **Invalid signature errors**: 
   - Verify the webhook secret in GitHub matches your Rails credentials
   - Ensure the payload is not being modified in transit (use HTTPS)

2. **Missing events**:
   - Check GitHub webhook delivery logs in repository settings
   - Verify event types are correctly selected in GitHub

3. **Timeout errors**:
   - Ensure webhook processing completes quickly or is offloaded to background jobs

### Testing Webhooks

GitHub provides a "Recent Deliveries" section in the webhook settings where you can:
- See delivery status
- Review request and response details
- Redeliver webhooks for testing

## Webhook Payload Structure

GitHub webhook payloads vary by event type. Examples:

### Push Event (Commits)

```json
{
  "ref": "refs/heads/main",
  "commits": [
    {
      "id": "abc123def456",
      "message": "Fix bug in feature",
      "timestamp": "2023-01-02T12:34:56Z",
      "author": {
        "name": "User Name",
        "email": "user@example.com"
      }
    }
  ],
  "repository": {
    "full_name": "username/repository"
  }
}
```

### Pull Request Event

```json
{
  "action": "opened",
  "pull_request": {
    "number": 42,
    "title": "Add new feature",
    "user": {
      "login": "username"
    },
    "base": {
      "ref": "main"
    },
    "head": {
      "ref": "feature-branch"
    }
  }
}
```

## References

- [GitHub Webhook Documentation](https://docs.github.com/en/webhooks/webhook-events-and-payloads)
- [GitHub IP Ranges](https://api.github.com/meta)
- [Securing Your Webhooks](https://docs.github.com/en/webhooks/securing-your-webhooks) 