# Message Batching

Ricqchet supports batching multiple messages into a single HTTP delivery, reducing the number of requests to your destination endpoint.

## How It Works

1. Messages with the same `tenant + destination_url + batch_key` are grouped together
2. A batch is dispatched when either:
   - The batch reaches the configured size limit
   - The batch timeout expires
3. The destination receives a JSON array containing all message payloads

## Configuration Headers

| Header | Description | Range | Default |
|--------|-------------|-------|---------|
| `Ricqchet-Batch-Key` | Unique identifier for the batch | any string | (required) |
| `Ricqchet-Batch-Size` | Maximum messages per batch | 1-1000 | 10 |
| `Ricqchet-Batch-Timeout` | Seconds before batch is sent | 1-3600 | 5 |

## Example

### Publishing Batched Messages

```bash
# First message starts a new batch
curl -X POST "http://localhost:4000/v1/publish" \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -H "Ricqchet-Destination: https://api.example.com/events" \
  -H "Ricqchet-Batch-Key: user-123-events" \
  -H "Ricqchet-Batch-Size: 3" \
  -H "Ricqchet-Batch-Timeout: 60" \
  -d '{"event": "page_view", "page": "/home"}'

# Second message added to same batch
curl -X POST "http://localhost:4000/v1/publish" \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -H "Ricqchet-Destination: https://api.example.com/events" \
  -H "Ricqchet-Batch-Key: user-123-events" \
  -d '{"event": "page_view", "page": "/products"}'

# Third message triggers immediate dispatch (batch size reached)
curl -X POST "http://localhost:4000/v1/publish" \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -H "Ricqchet-Destination: https://api.example.com/events" \
  -H "Ricqchet-Batch-Key: user-123-events" \
  -d '{"event": "add_to_cart", "product_id": 456}'
```

### Delivered Payload

The destination receives a JSON array:

```json
[
  {"event": "page_view", "page": "/home"},
  {"event": "page_view", "page": "/products"},
  {"event": "add_to_cart", "product_id": 456}
]
```

## Batch Lifecycle

```
collecting → pending → dispatched → delivered/failed
```

| Status | Description |
|--------|-------------|
| `collecting` | Accepting new messages |
| `pending` | Ready for dispatch (size/timeout reached) |
| `dispatched` | Currently being delivered |
| `delivered` | Successfully delivered (2xx response) |
| `failed` | Failed after all retries |

## Important Behaviors

### Batch Key Scope

Batches are scoped to:
- Tenant (your API key's organization)
- Destination URL (exact match)
- Batch key

This means the same batch key can be used for different destinations without conflict.

### First Message Wins

The first message in a batch determines:
- Maximum batch size
- Batch timeout
- Headers to forward

Subsequent messages with different size/timeout values are ignored.

### Retry Behavior

If batch delivery fails:
- The entire batch is retried with exponential backoff
- Individual messages cannot be retried separately
- All messages in the batch share the same fate

### Ordering

Messages within a batch are delivered in the order they were received.

### Cannot Combine with Fan-out

Batching and fan-out are mutually exclusive. If you need to send to multiple destinations, use fan-out without batching, or send separate batched requests to each destination.

## Use Cases

### Event Aggregation

Collect user events and deliver them periodically:

```bash
# Collect events for 30 seconds, max 100 per batch
curl -X POST "http://localhost:4000/v1/publish" \
  -H "Authorization: Bearer <api_key>" \
  -H "Ricqchet-Destination: https://analytics.example.com/events" \
  -H "Ricqchet-Batch-Key: user-456-session" \
  -H "Ricqchet-Batch-Size: 100" \
  -H "Ricqchet-Batch-Timeout: 30" \
  -d '{"event": "click", "element": "buy-button"}'
```

### Reducing Webhook Load

Instead of sending 1000 individual webhooks:

```bash
# Batch 50 notifications together
curl -X POST "http://localhost:4000/v1/publish" \
  -H "Authorization: Bearer <api_key>" \
  -H "Ricqchet-Destination: https://slack.example.com/webhook" \
  -H "Ricqchet-Batch-Key: alerts-channel" \
  -H "Ricqchet-Batch-Size: 50" \
  -H "Ricqchet-Batch-Timeout: 10" \
  -d '{"alert": "Server CPU high", "severity": "warning"}'
```

## Constraints

- **Batch size**: 1 to 1,000 messages
- **Batch timeout**: 1 to 3,600 seconds (1 hour)
- **Payload size**: Each individual message payload is stored; total batch size should be considered for your destination endpoint's limits
- **Fan-out**: Cannot be combined with batching
