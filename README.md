# Relay

HTTP message queuing service with guaranteed delivery, similar to [Upstash QStash](https://upstash.com/docs/qstash/overall/getstarted).

Relay allows serverless functions to POST events that are queued and delivered to destination URLs with automatic retries and exponential backoff.

## Features

- **Guaranteed delivery** with automatic retries and exponential backoff
- **Multi-tenant** API key authentication
- **Deduplication** to prevent duplicate message processing
- **Delayed delivery** with configurable scheduling
- **Message status tracking** with detailed attempt history
- **Header forwarding** to destination endpoints

## Tech Stack

- Elixir 1.18+ / OTP 27+
- Phoenix 1.8+ (API only)
- PostgreSQL 15+
- Oban for reliable job processing
- Req for HTTP client

## Getting Started

### Prerequisites

- Erlang 27+
- Elixir 1.18+
- PostgreSQL 15+

If using [mise](https://mise.jdx.dev/), run `mise install` to set up the correct versions.

### Setup

```bash
# Install dependencies
mix setup

# Start the server
mix phx.server
```

### Create a Tenant

```elixir
# In iex -S mix
{:ok, tenant} = Relay.Tenants.create_tenant(%{name: "My App"})
# Save the api_key - it's only shown once!
tenant.api_key
```

## API Reference

All API endpoints (except `/health`) require authentication via Bearer token:

```
Authorization: Bearer <api_key>
```

### Health Check

```
GET /health
```

Returns `{"status": "ok"}` - no authentication required.

### Publish Message

```
POST /v1/publish/{destination_url}
```

Publishes a message to be delivered to the destination URL.

**Headers:**

| Header | Description | Example |
|--------|-------------|---------|
| `Relay-Delay` | Delay before first attempt | `30s`, `5m`, `2h`, `1d` |
| `Relay-Dedup-Key` | Deduplication key | `order-123` |
| `Relay-Dedup-TTL` | Dedup window in seconds (default: 300) | `600` |
| `Relay-Retries` | Override max retries (default: 3) | `5` |
| `Relay-Forward-*` | Headers to forward (prefix stripped) | `Relay-Forward-X-Custom: value` |

**Example:**

```bash
curl -X POST "http://localhost:4000/v1/publish/https://api.example.com/webhook" \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -H "Relay-Delay: 30s" \
  -H "Relay-Dedup-Key: order-123" \
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
- `pending` - Waiting to be dispatched
- `dispatched` - Currently being delivered
- `delivered` - Successfully delivered (2xx response)
- `failed` - Failed after all retries exhausted

### Cancel Message

```
DELETE /v1/messages/{id}
```

Cancels a pending message. Returns 409 if already dispatched.

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

## Retry Behavior

Failed deliveries are retried with exponential backoff:

| Attempt | Delay |
|---------|-------|
| 1 | 10 seconds |
| 2 | 30 seconds |
| 3 | 90 seconds |
| 4 | 270 seconds (~4.5 min) |
| 5+ | Continues 3x growth, max 8 hours |

A delivery is considered failed if:
- HTTP status is not 2xx
- Connection timeout (30s receive, 10s connect)
- Network error

## Delivered Headers

When Relay delivers a message, it includes these headers:

| Header | Description |
|--------|-------------|
| `Content-Type` | Original content type |
| `User-Agent` | `Relay/1.0` |
| `X-Relay-Message-Id` | Message UUID |
| `X-Relay-Attempt` | Current attempt number |
| + any `Relay-Forward-*` headers | Forwarded with prefix stripped |

## Development

### Running Tests

```bash
mix test
```

### Code Quality

```bash
# Format code
mix format

# Static analysis
mix credo --strict

# Type checking (first run builds PLT)
mix dialyzer
```

### Database

```bash
# Create and migrate
mix ecto.setup

# Reset database
mix ecto.reset

# Run migrations only
mix ecto.migrate
```

## Configuration

Key configuration options in `config/`:

```elixir
# config/config.exs
config :relay, Oban,
  repo: Relay.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [delivery: 50]  # 50 concurrent delivery workers
```

## License

MIT
