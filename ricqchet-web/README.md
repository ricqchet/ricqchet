# Ricqchet

**Self-hosted HTTP message relay and real-time channels.** Publish messages once — Ricqchet handles guaranteed delivery, retries, fan-out, batching, and scheduling. Connect clients with WebSocket channels that include history, presence, and cache.

> Own your infrastructure. No per-message pricing, no vendor lock-in, no data leaving your stack.

> **Part of the [Ricqchet monorepo](../README.md).** This is the server (`ricqchet-web/`); the official TypeScript client lives in [`../ricqchet-ts-client/`](../ricqchet-ts-client/). Run all `mix` commands below from this `ricqchet-web/` directory.

---

## What Ricqchet does

Ricqchet gives you two first-class capabilities in a single service:

**Message relay** — your application POSTs an event to Ricqchet, which queues it, handles retries with exponential backoff, verifies delivery with HMAC signatures, and routes failures to a dead-letter queue. Think Upstash QStash, self-hosted and open-source.

**Real-time channels** — broadcast events to WebSocket clients instantly. Public, private (auth-gated), and presence (member-tracking) channels with event history, cache channels (last-event-on-join), client-to-client messaging, and per-namespace configuration. Think Pusher or Ably, on your own infrastructure.

---

## Features

### Message Relay

| Feature | Details |
|---------|---------|
| **Guaranteed delivery** | Automatic retries with exponential backoff (10s → 30s → 90s → 270s → max 8h) |
| **Deduplication** | Configurable TTL window (default 5m, max 24h) — rejects duplicates with 409 |
| **Delayed delivery** | Schedule messages up to 7 days ahead (`30s`, `5m`, `2h`, `1d`) |
| **Fan-out** | Broadcast to up to 100 destinations in a single API call |
| **Batching** | Group messages into a single delivery — dispatched by size or timeout |
| **Header forwarding** | `Ricqchet-Forward-*` headers delivered with prefix stripped |
| **HMAC signatures** | Every delivery signed with `X-Ricqchet-Signature` (HMAC-SHA256) |
| **Dead-letter queue** | Per-application DLQ webhook fires when all retries are exhausted |
| **Flow control** | Per-destination parallelism and rate limiting, cluster-coordinated via PostgreSQL |
| **Cancellation** | Cancel pending messages before dispatch |

### Real-Time Channels

| Feature | Details |
|---------|---------|
| **Channel types** | Public, Private (`private-` prefix), Presence (`presence-` prefix) |
| **Event history** | Configurable retention per namespace — query via API or recover on reconnect |
| **Cache channels** | New subscribers receive the last published event immediately |
| **Presence tracking** | See who's connected with `user_id` and custom metadata |
| **Client events** | Peer-to-peer messaging on private/presence channels (rate-limited, `client-` prefix) |
| **Browser-safe keys** | `subscribe`-scoped API keys connect the WebSocket but are rejected on every REST endpoint — safe to embed in front-end code |
| **Missed-event recovery** | Rejoin with `last_event_id` to catch up after disconnect |
| **Namespace config** | Pattern-based settings (`chat-*`, `orders.us.*`) for max members, history, auth, webhooks |
| **Lifecycle webhooks** | Receive events when channels open/close or members join/leave |

### Platform

- **LiveView dashboard** — manage applications, API keys, channels, and team members; monitor delivery in real time
- **Role-based access** — `admin` / `member` / `viewer` roles with granular permissions
- **OpenAPI docs** — full Swagger UI at `/api/docs`
- **Structured logging** — metadata-rich log output for easy querying
- **Telemetry** — Phoenix, Ecto, Oban, and custom delivery metrics
- **Self-hosted, single-org** — one deployment per team; no sign-up flow, no multi-tenant complexity

---

## Tech Stack

- Elixir 1.18+ / OTP 27+
- Phoenix 1.8+ (JSON API + LiveView dashboard)
- PostgreSQL 15+
- Oban — reliable background job processing
- Req — HTTP client

---

## Getting Started

### Prerequisites

- Erlang 27+, Elixir 1.18+, PostgreSQL 15+

Using [mise](https://mise.jdx.dev/)? Run `mise install` from the repo root.

### Setup

```bash
mix setup        # install deps, create DB, run migrations, seed
mix phx.server   # start dev server
```

API docs are at [`/api/docs`](http://localhost:4000/api/docs) once the server is running.

### First-Run Setup

On first run, Ricqchet creates a default organization and an initial **admin** user. Credentials are printed to the console.

Configure the admin before setup (optional):

```bash
ADMIN_EMAIL=admin@yourco.com ADMIN_PASSWORD=a-strong-password mix ecto.setup
```

If `ADMIN_PASSWORD` is not set, a secure password is generated and printed once — save it before the terminal scrolls.

**Sign in at `/login` and change your password immediately** (Settings → Change password).

Locked out? Reset without email:

```bash
mix ricqchet.reset_admin_password admin@yourco.com
```

Admins add team members (with `member` or `viewer` roles) from the **Team** page or `POST /v1/tenant/users`.

For production releases:

```bash
bin/ricqchet eval "Ricqchet.Release.migrate()"
bin/ricqchet eval "Ricqchet.Release.seed()"
```

---

## Quick API Examples

All relay and channel endpoints require an API key:

```
Authorization: Bearer <api_key>
```

Management endpoints (applications, users, stats) use JWT tokens from `POST /v1/auth/login`.

### Publish a message

```bash
curl -X POST http://localhost:4000/v1/publish \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -H "Ricqchet-Destination: https://api.example.com/webhook" \
  -H "Ricqchet-Delay: 30s" \
  -H "Ricqchet-Dedup-Key: order-123" \
  -d '{"event": "order.created", "id": 123}'
```

```json
{"message_id": "550e8400-e29b-41d4-a716-446655440000"}
```

### Fan-out to multiple destinations

```bash
curl -X POST http://localhost:4000/v1/publish \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -H "Ricqchet-Fan-Out: https://api1.example.com/hook, https://api2.example.com/hook" \
  -d '{"event": "order.created", "id": 123}'
```

```json
{"message_ids": ["550e8400-...", "550e8400-..."]}
```

### Batch messages

```bash
curl -X POST http://localhost:4000/v1/publish \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -H "Ricqchet-Destination: https://api.example.com/webhook" \
  -H "Ricqchet-Batch-Key: user-123-events" \
  -H "Ricqchet-Batch-Size: 25" \
  -H "Ricqchet-Batch-Timeout: 10" \
  -d '{"event": "page.viewed", "path": "/pricing"}'
```

### Publish to a channel

```bash
curl -X POST http://localhost:4000/v1/channels/events \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -d '{"channel": "orders", "event": "order.updated", "data": {"id": 123, "status": "shipped"}}'
```

### Connect a WebSocket client (JavaScript)

```js
const socket = new WebSocket(
  `ws://localhost:4000/socket/websocket?api_key=<api_key>&user_id=<user_id>`
);

// Subscribe to a channel
socket.send(JSON.stringify({
  topic: "orders",
  event: "phx_join",
  payload: {},
  ref: "1"
}));
```

Private channels require an auth endpoint — see [docs/channels.md](docs/channels.md).

### Check message status

```bash
curl http://localhost:4000/v1/messages/550e8400-... \
  -H "Authorization: Bearer <api_key>"
```

```json
{
  "id": "550e8400-...",
  "status": "delivered",
  "attempts": 1,
  "max_retries": 3,
  "last_response_status": 200,
  "completed_at": "2024-01-15T10:30:31Z"
}
```

---

## Verifying Signatures

Every delivered message includes an `X-Ricqchet-Signature` header. Verify it at your endpoint:

```
X-Ricqchet-Signature: t=1705316400,v1=a1b2c3...
```

```elixir
signature = "t=1705316400,v1=a1b2c3..."
[_, ts] = String.split(signature, "t=", parts: 2) |> List.first() |> String.split(",v1=")
expected = :crypto.mac(:hmac, :sha256, signing_secret, "#{ts}.#{raw_body}") |> Base.encode16(case: :lower)
```

Get your tenant's signing secret from `GET /v1/signing-secret` (admin only) or the Settings page.

---

## Retry Behavior

| Attempt | Delay |
|---------|-------|
| 1 | 10 seconds |
| 2 | 30 seconds |
| 3 | 90 seconds |
| 4 | 270 seconds (~4.5 min) |
| 5+ | 3× growth, max 8 hours |

Default is 3 retries. Override per-message with `Ricqchet-Retries: 0` (fire-and-forget) to `Ricqchet-Retries: 10`. When all retries are exhausted, the message is sent to the application's DLQ webhook (if configured).

---

## Delivery Headers

| Header | Description |
|--------|-------------|
| `Content-Type` | From original publish request |
| `User-Agent` | `Ricqchet/1.0` |
| `X-Ricqchet-Message-Id` | Message UUID |
| `X-Ricqchet-Attempt` | Current attempt number (1-based) |
| `X-Ricqchet-Signature` | HMAC-SHA256 signature for verification |
| `Ricqchet-Forward-*` headers | Forwarded with prefix stripped |

---

## Documentation

- [Overview](docs/overview.md) — how Ricqchet works, core concepts
- [API Reference](docs/api-reference.md) — all endpoints, headers, and examples
- [Authentication](docs/authentication.md) — users, roles, API keys, and JWT
- [Channels](docs/channels.md) — WebSocket channels, presence, history, and namespaces
- [Batching](docs/batching.md) — message batching configuration
- [Delivery](docs/delivery.md) — retry behavior, timeouts, and DLQ
- [Configuration](docs/configuration.md) — environment variables and runtime settings
- [Receiving Webhooks](docs/receiving-webhooks.md) — guide for webhook consumers

Interactive API docs: [`/api/docs`](http://localhost:4000/api/docs)

---

## Development

### Running Tests

```bash
mix test              # all tests
mix test --failed     # re-run failures only
```

### Code Quality

```bash
mix format            # auto-format
mix credo --strict    # static analysis
mix dialyzer          # type checking
mix precommit         # all of the above (required before committing)
```

### Database

```bash
mix ecto.setup        # create, migrate, seed
mix ecto.reset        # drop and recreate
mix ecto.migrate      # migrations only
```

---

## Commit Conventions

This repo uses [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add webhook signature verification
fix: correct retry backoff calculation
docs: update api reference for channels
refactor(delivery): extract retry logic to module
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`

---

## Client Libraries

- [TypeScript Client](../ricqchet-ts-client) — in this monorepo (`@ricqchet/client`)
- [Elixir Client](https://github.com/ricqchet/elixir-client)

---

## License

MIT
