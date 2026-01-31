# API Reference

All API endpoints (except `/health`, `/api/openapi`, and `/api/docs`) require authentication via Bearer token:

```
Authorization: Bearer <api_key>
```

## Endpoints

### Health Check

```
GET /health
```

Returns service health status. No authentication required.

**Response (200 OK):**

```json
{"status": "ok"}
```

### OpenAPI Specification

```
GET /api/openapi
```

Returns the OpenAPI 3.0 specification. No authentication required.

### Swagger UI

```
GET /api/docs
```

Interactive API documentation. No authentication required.

### Publish Message

```
POST /v1/publish
```

Publishes a message to be queued and delivered to the destination URL.

**Headers:**

| Header | Description | Example |
|--------|-------------|---------|
| `Ricqchet-Destination` | Destination URL (required unless using fan-out) | `https://api.example.com/webhook` |
| `Ricqchet-Fan-Out` | Comma-separated URLs for fan-out (max 100) | `https://api1.com, https://api2.com` |
| `Ricqchet-Delay` | Delay before first delivery attempt (max: 7 days) | `30s`, `5m`, `2h`, `1d` |
| `Ricqchet-Dedup-Key` | Deduplication key to prevent duplicate processing | `order-123` |
| `Ricqchet-Dedup-TTL` | Dedup window in seconds (default: 300) | `600` |
| `Ricqchet-Retries` | Override max retries (default: 3) | `5` |
| `Ricqchet-Forward-*` | Headers to forward to destination (prefix stripped) | `Ricqchet-Forward-X-Custom: value` |
| `Ricqchet-Batch-Key` | Group messages into a batch | `user-123-events` |
| `Ricqchet-Batch-Size` | Max messages per batch (1-1000, default: 10) | `50` |
| `Ricqchet-Batch-Timeout` | Seconds before batch is sent (1-3600, default: 5) | `30` |

**Example:**

```bash
curl -X POST "http://localhost:4000/v1/publish" \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -H "Ricqchet-Destination: https://api.example.com/webhook" \
  -H "Ricqchet-Delay: 30s" \
  -H "Ricqchet-Dedup-Key: order-123" \
  -d '{"event": "order.created", "data": {"id": 123}}'
```

**Response (202 Accepted):**

```json
{"message_id": "550e8400-e29b-41d4-a716-446655440000"}
```

**Response (409 Conflict - duplicate):**

```json
{
  "error": "duplicate_message",
  "message": "A message with this dedup_key already exists: 550e8400-..."
}
```

### Get Message Status

```
GET /v1/messages/{id}
```

Retrieves the status and details of a message.

**Example:**

```bash
curl "http://localhost:4000/v1/messages/550e8400-e29b-41d4-a716-446655440000" \
  -H "Authorization: Bearer <api_key>"
```

**Response:**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "delivered",
  "destination_url": "https://api.example.com/webhook",
  "method": "POST",
  "attempts": 1,
  "max_retries": 3,
  "created_at": "2024-01-15T10:30:00Z",
  "scheduled_at": "2024-01-15T10:30:30Z",
  "dispatched_at": "2024-01-15T10:30:30Z",
  "completed_at": "2024-01-15T10:30:31Z",
  "last_error": null,
  "last_response_status": 200
}
```

**Status values:**

| Status | Description |
|--------|-------------|
| `pending` | Waiting to be dispatched |
| `dispatched` | Currently being delivered |
| `delivered` | Successfully delivered (2xx response) |
| `failed` | Failed after all retries exhausted |

### Cancel Message

```
DELETE /v1/messages/{id}
```

Cancels a pending message. Returns 409 if the message has already been dispatched.

**Example:**

```bash
curl -X DELETE "http://localhost:4000/v1/messages/550e8400-..." \
  -H "Authorization: Bearer <api_key>"
```

**Response (200 OK):**

```json
{"cancelled": true}
```

**Response (409 Conflict):**

```json
{"error": "already_dispatched", "message": "Message already dispatched"}
```

## Fan-out

Use the `Ricqchet-Fan-Out` header to broadcast the same message to multiple destinations with a single API call. This creates separate messages for each destination, each with its own delivery tracking.

**Example:**

```bash
curl -X POST "http://localhost:4000/v1/publish" \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -H "Ricqchet-Fan-Out: https://api1.example.com/webhook, https://api2.example.com/webhook, https://api3.example.com/webhook" \
  -d '{"event": "order.created", "data": {"id": 123}}'
```

**Response (202 Accepted):**

```json
{
  "message_ids": [
    "550e8400-e29b-41d4-a716-446655440000",
    "550e8400-e29b-41d4-a716-446655440001",
    "550e8400-e29b-41d4-a716-446655440002"
  ]
}
```

**Fan-out constraints:**

- Maximum 100 destinations per request
- Cannot be combined with `Ricqchet-Destination` (use one or the other)
- Cannot be combined with batching (`Ricqchet-Batch-Key`)
- Each destination gets its own message with independent retry behavior

## Header Forwarding

To forward custom headers to the destination endpoint, prefix them with `Ricqchet-Forward-`. The prefix is stripped when delivering.

**Example:**

```bash
curl -X POST "http://localhost:4000/v1/publish" \
  -H "Authorization: Bearer <api_key>" \
  -H "Ricqchet-Destination: https://api.example.com/webhook" \
  -H "Ricqchet-Forward-X-Correlation-Id: abc-123" \
  -H "Ricqchet-Forward-X-Source: my-service" \
  -d '{"event": "test"}'
```

The destination receives:

```
X-Correlation-Id: abc-123
X-Source: my-service
```

**Blocked headers** (cannot be forwarded for security):

- `host`, `content-length`, `transfer-encoding`
- `connection`, `keep-alive`, `proxy-*`
- `te`, `trailer`, `upgrade`

## Deduplication

Prevent duplicate message processing by providing a deduplication key:

```bash
curl -X POST "http://localhost:4000/v1/publish" \
  -H "Authorization: Bearer <api_key>" \
  -H "Ricqchet-Destination: https://api.example.com/webhook" \
  -H "Ricqchet-Dedup-Key: order-123" \
  -H "Ricqchet-Dedup-TTL: 600" \
  -d '{"event": "order.created"}'
```

- Messages with the same `tenant + dedup_key` within the TTL window are rejected with 409
- Default TTL is 300 seconds (5 minutes)
- TTL can be customized per-message up to 86400 seconds (24 hours)

## Delayed Delivery

Schedule messages for future delivery:

```bash
curl -X POST "http://localhost:4000/v1/publish" \
  -H "Authorization: Bearer <api_key>" \
  -H "Ricqchet-Destination: https://api.example.com/webhook" \
  -H "Ricqchet-Delay: 1h" \
  -d '{"event": "reminder"}'
```

**Supported delay formats:**

| Format | Description | Example |
|--------|-------------|---------|
| `Ns` | N seconds | `30s` |
| `Nm` | N minutes | `5m` |
| `Nh` | N hours | `2h` |
| `Nd` | N days | `1d` |

Maximum delay: 7 days
