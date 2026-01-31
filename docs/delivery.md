# Message Delivery

## Retry Behavior

Failed deliveries are retried with exponential backoff:

| Attempt | Delay |
|---------|-------|
| 1 | 10 seconds |
| 2 | 30 seconds |
| 3 | 90 seconds |
| 4 | 270 seconds (~4.5 min) |
| 5+ | Continues 3x growth, max 8 hours |

### What Triggers a Retry

A delivery is considered failed and will be retried if:

- HTTP response status is not 2xx
- Connection timeout (30 second receive timeout, 10 second connect timeout)
- Network error (DNS failure, connection refused, etc.)

### Customizing Retries

Override the default retry count (3) per-message:

```bash
curl -X POST "http://localhost:4000/v1/publish/https://api.example.com/webhook" \
  -H "Authorization: Bearer <api_key>" \
  -H "Ricqchet-Retries: 5" \
  -d '{"event": "important"}'
```

Set `Ricqchet-Retries: 0` for fire-and-forget (no retries).

## Delivered Headers

When Ricqchet delivers a message, it includes these headers:

| Header | Description |
|--------|-------------|
| `Content-Type` | Original content type from publish request |
| `User-Agent` | `Ricqchet/1.0` |
| `X-Ricqchet-Message-Id` | Message UUID for tracking |
| `X-Ricqchet-Attempt` | Current attempt number (1-based) |
| + forwarded headers | Any `Ricqchet-Forward-*` headers with prefix stripped |

### Example Request to Destination

```http
POST /webhook HTTP/1.1
Host: api.example.com
Content-Type: application/json
User-Agent: Ricqchet/1.0
X-Ricqchet-Message-Id: 550e8400-e29b-41d4-a716-446655440000
X-Ricqchet-Attempt: 1
X-Correlation-Id: abc-123

{"event": "order.created", "data": {"id": 123}}
```

## Timeouts

| Timeout | Value |
|---------|-------|
| Connection timeout | 10 seconds |
| Receive timeout | 30 seconds |

If your endpoint needs longer processing time, consider:
- Returning 202 Accepted immediately and processing asynchronously
- Using a queue on your end to handle the work

## Success Criteria

A delivery is considered successful when:
- HTTP response status is 2xx (200-299)

The response body is stored for debugging but not used to determine success.

## Message States

```
pending → dispatched → delivered
                    ↘ failed
```

| State | Description |
|-------|-------------|
| `pending` | Queued, waiting to be picked up by dispatcher |
| `dispatched` | Actively being delivered (in-flight) |
| `delivered` | Successfully delivered (2xx response received) |
| `failed` | All retry attempts exhausted |

## Idempotency

Your webhook endpoint should be idempotent. While Ricqchet prevents duplicate publishing via deduplication keys, network issues could cause the same message to be delivered more than once.

Use the `X-Ricqchet-Message-Id` header to detect and handle duplicate deliveries on your end.

## URL Validation

Destination URLs are validated before acceptance:

- Must be valid HTTP or HTTPS URL
- Must have a valid host
- Private/internal IPs may be blocked depending on configuration

## Cancellation

Messages can be cancelled while in `pending` state:

```bash
curl -X DELETE "http://localhost:4000/v1/messages/<message_id>" \
  -H "Authorization: Bearer <api_key>"
```

Once a message reaches `dispatched` state, it cannot be cancelled.
