# Receiving Webhooks

This guide is for developers building endpoints that receive messages from Ricqchet.

## What to Expect

When Ricqchet delivers a message to your endpoint, you'll receive a standard HTTP POST request with:

```http
POST /your/webhook HTTP/1.1
Host: your-api.example.com
Content-Type: application/json
User-Agent: Ricqchet/1.0
X-Ricqchet-Message-Id: 550e8400-e29b-41d4-a716-446655440000
X-Ricqchet-Attempt: 1

{"event": "order.created", "data": {"id": 123}}
```

## Ricqchet Headers

Every delivery includes these headers:

| Header | Description | Example |
|--------|-------------|---------|
| `X-Ricqchet-Message-Id` | Unique identifier for this message | `550e8400-e29b-41d4-a716-446655440000` |
| `X-Ricqchet-Attempt` | Which attempt this is (1-based) | `1`, `2`, `3` |
| `User-Agent` | Always `Ricqchet/1.0` | `Ricqchet/1.0` |
| `Content-Type` | From the original publish request | `application/json` |

## Forwarded Headers

The publisher can forward custom headers to your endpoint. These arrive with their original names (the `Ricqchet-Forward-` prefix is stripped).

Common forwarded headers you might see:

| Header | Typical Use |
|--------|-------------|
| `X-Correlation-Id` | Request tracing across services |
| `X-Request-Id` | Unique request identifier |
| `X-Source` | Originating service name |
| `X-Tenant-Id` | Multi-tenant context |
| `Authorization` | Auth token for your endpoint |

## Response Requirements

### Success

Return any 2xx status code to indicate successful delivery:

```http
HTTP/1.1 200 OK
Content-Type: application/json

{"received": true}
```

The response body is stored for debugging but doesn't affect delivery status.

### Failure

Any non-2xx response triggers a retry (if retries remain):

```http
HTTP/1.1 500 Internal Server Error
Content-Type: application/json

{"error": "Database unavailable"}
```

### Timeouts

Ricqchet waits up to 30 seconds for your response. If your endpoint needs longer:

1. Return `202 Accepted` immediately
2. Process the message asynchronously
3. Handle the work in a background job

```http
HTTP/1.1 202 Accepted
Content-Type: application/json

{"status": "processing", "job_id": "abc123"}
```

## Handling Retries

Your endpoint may receive the same message multiple times. This happens when:

- Your endpoint returned an error and Ricqchet retried
- Network issues caused a timeout after your endpoint processed the request
- Ricqchet's delivery confirmation was lost

### Be Idempotent

Design your endpoint to handle duplicate deliveries safely:

```python
def handle_webhook(request):
    message_id = request.headers.get('X-Ricqchet-Message-Id')

    # Check if already processed
    if already_processed(message_id):
        return Response(status=200)  # Success - don't process again

    # Process the message
    process(request.json)

    # Mark as processed
    mark_processed(message_id)

    return Response(status=200)
```

### Using the Attempt Number

The `X-Ricqchet-Attempt` header tells you which attempt this is:

```python
def handle_webhook(request):
    attempt = int(request.headers.get('X-Ricqchet-Attempt', 1))

    if attempt > 1:
        log.warning(f"Retry attempt {attempt} for message")

    # Process normally
    process(request.json)
```

## Receiving Batched Messages

When the publisher uses batching, you receive a JSON array instead of a single object:

```http
POST /your/webhook HTTP/1.1
Content-Type: application/json
X-Ricqchet-Message-Id: 550e8400-e29b-41d4-a716-446655440000

[
  {"event": "page_view", "page": "/home"},
  {"event": "page_view", "page": "/products"},
  {"event": "add_to_cart", "product_id": 456}
]
```

Handle both single messages and arrays:

```python
def handle_webhook(request):
    payload = request.json

    # Normalize to list
    messages = payload if isinstance(payload, list) else [payload]

    for message in messages:
        process(message)

    return Response(status=200)
```

### Batch Atomicity

A batch is all-or-nothing. If you return an error:

- The entire batch is retried
- Individual messages cannot be acknowledged separately
- Ensure you can handle the full batch or reject it entirely

## IP Allowlisting

If you restrict incoming traffic by IP, contact the Ricqchet operator for the list of delivery server IPs. Be aware these may change if the service scales or migrates.

## Debugging

### Check Message Status

Ask the publisher to look up message status using the message ID from your logs:

```
GET /v1/messages/550e8400-e29b-41d4-a716-446655440000
```

This shows:

- Number of attempts made
- Last response status your endpoint returned
- Any error messages
- Timestamps for each stage

### Log the Ricqchet Headers

Always log `X-Ricqchet-Message-Id` and `X-Ricqchet-Attempt` to correlate with Ricqchet's delivery records:

```python
def handle_webhook(request):
    log.info(
        "Received webhook",
        message_id=request.headers.get('X-Ricqchet-Message-Id'),
        attempt=request.headers.get('X-Ricqchet-Attempt')
    )
```

## Security Considerations

### Verify the Source

If you need to verify that requests actually come from Ricqchet (and not a malicious actor):

1. **Shared secret**: Have the publisher forward an `Authorization` header with a token you both know
2. **IP allowlist**: Restrict to Ricqchet's IP addresses
3. **Request signing**: Have the publisher forward a signature header you can verify

Example with shared secret:

```python
def handle_webhook(request):
    expected_token = os.environ['WEBHOOK_SECRET']
    actual_token = request.headers.get('Authorization', '').replace('Bearer ', '')

    if not secrets.compare_digest(expected_token, actual_token):
        return Response(status=401)

    process(request.json)
    return Response(status=200)
```

### Validate Payloads

Don't trust the payload blindly:

- Validate the JSON structure
- Check required fields exist
- Sanitize any data before using in queries or commands

## Checklist

Before going live, ensure your endpoint:

- [ ] Returns 2xx for successful processing
- [ ] Handles duplicate deliveries idempotently
- [ ] Responds within 30 seconds (or returns 202 and processes async)
- [ ] Logs `X-Ricqchet-Message-Id` for debugging
- [ ] Handles both single messages and batched arrays (if batching is used)
- [ ] Validates incoming payloads
- [ ] Has appropriate authentication (if required)
