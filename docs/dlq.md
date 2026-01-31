# Dead Letter Queue (DLQ)

When a message or batch permanently fails (exhausts all retry attempts), Ricqchet can send a webhook notification to a configured DLQ destination. This allows you to monitor failures, trigger alerts, or implement custom failure handling.

## Configuration

Configure a DLQ destination URL on an application. When messages published through that application's API keys fail permanently, a webhook notification is sent to the DLQ URL.

### Setting DLQ Destination

The `dlq_destination_url` is an optional field on applications. Set it when creating or updating an application:

```elixir
# When creating an application
{:ok, app} = Applications.create_application(tenant, %{
  name: "My App",
  dlq_destination_url: "https://my-monitoring.example.com/dlq"
})

# When updating an application
{:ok, app} = Applications.update_application(app, %{
  dlq_destination_url: "https://my-monitoring.example.com/dlq"
})
```

To disable DLQ notifications, set the URL to `nil` or omit it entirely.

## Webhook Payload

When a message or batch fails, a JSON webhook is sent to the configured DLQ URL.

### Message Failure

```json
{
  "event": "message.failed",
  "timestamp": "2026-01-31T12:00:00Z",
  "message": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "destination_url": "https://api.example.com/webhook",
    "method": "POST",
    "status": "failed",
    "attempts": 3,
    "max_retries": 3,
    "last_error": "HTTP 500",
    "last_response_status": 500,
    "created_at": "2026-01-31T10:00:00Z",
    "failed_at": "2026-01-31T12:00:00Z"
  },
  "application": {
    "id": "app-uuid",
    "name": "My App"
  },
  "tenant": {
    "id": "tenant-uuid",
    "name": "Acme Corp"
  }
}
```

### Batch Failure

```json
{
  "event": "batch.failed",
  "timestamp": "2026-01-31T12:00:00Z",
  "batch": {
    "id": "batch-uuid",
    "destination_url": "https://api.example.com/batch-webhook",
    "batch_key": "user-123-events",
    "message_count": 15,
    "status": "failed",
    "attempts": 3,
    "max_retries": 3,
    "last_error": "Connection refused",
    "last_response_status": null,
    "created_at": "2026-01-31T10:00:00Z",
    "failed_at": "2026-01-31T12:00:00Z"
  },
  "application": {
    "id": "app-uuid",
    "name": "My App"
  },
  "tenant": {
    "id": "tenant-uuid",
    "name": "Acme Corp"
  }
}
```

## Payload Fields

| Field | Description |
|-------|-------------|
| `event` | Either `message.failed` or `batch.failed` |
| `timestamp` | ISO 8601 timestamp when the notification was generated |
| `message` / `batch` | Details about the failed entity |
| `application` | The application the message was published through |
| `tenant` | The tenant that owns the application |

### Message/Batch Fields

| Field | Description |
|-------|-------------|
| `id` | Unique identifier |
| `destination_url` | The URL delivery was attempted to |
| `method` | HTTP method (messages only, usually `POST`) |
| `batch_key` | Batch grouping key (batches only) |
| `message_count` | Number of messages in batch (batches only) |
| `status` | Always `failed` for DLQ notifications |
| `attempts` | Number of delivery attempts made |
| `max_retries` | Maximum retries configured |
| `last_error` | Description of the final error |
| `last_response_status` | HTTP status code if available |
| `created_at` | When the message/batch was created |
| `failed_at` | When the message/batch was marked failed |

## DLQ Notification Delivery

DLQ notifications are delivered via an Oban job queue with the following behavior:

| Setting | Value |
|---------|-------|
| Queue | `dlq_notifications` |
| Max attempts | 3 |
| Connection timeout | 10 seconds |
| Receive timeout | 30 seconds |

### Headers Sent

```
Content-Type: application/json
User-Agent: Ricqchet-DLQ/1.0
```

### Success Criteria

A DLQ notification is considered successful when the endpoint returns a 2xx status code.

### Retry Behavior

If the DLQ notification fails, Oban retries with its default exponential backoff. After 3 failed attempts, the notification is abandoned (it will not be retried further).

## Best Practices

1. **Monitor your DLQ endpoint** - If DLQ notifications fail, you won't know about message failures
2. **Return 200 quickly** - Process notifications asynchronously to avoid timeouts
3. **Be idempotent** - DLQ notifications could potentially be delivered more than once
4. **Log the message ID** - Use the `message.id` or `batch.id` to correlate with your systems

## Example: Alerting on Failures

A simple DLQ endpoint that sends alerts:

```python
from flask import Flask, request
import requests

app = Flask(__name__)

@app.route('/dlq', methods=['POST'])
def handle_dlq():
    data = request.json
    event = data['event']

    if event == 'message.failed':
        msg = data['message']
        alert(f"Message {msg['id']} failed after {msg['attempts']} attempts: {msg['last_error']}")
    elif event == 'batch.failed':
        batch = data['batch']
        alert(f"Batch {batch['id']} ({batch['message_count']} messages) failed: {batch['last_error']}")

    return '', 200

def alert(message):
    # Send to Slack, PagerDuty, email, etc.
    pass
```
