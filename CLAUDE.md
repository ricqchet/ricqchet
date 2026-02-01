# CLAUDE.md

Ricqchet is an HTTP message relay service with guaranteed delivery, retries, fan-out, batching, and scheduling. Built with Phoenix 1.8 (API-only) and Oban for job processing.

## Quick Reference

```bash
mix setup              # Install deps, create DB, run migrations
mix phx.server         # Start dev server (API docs at /api/docs)
mix test               # Run tests
mix test --failed      # Re-run failed tests only
mix precommit          # Pre-commit checks (REQUIRED before committing)
```

## Before Committing

**REQUIRED:** Run the precommit alias before every commit:

```bash
mix precommit
```

This runs (in order):
1. `compile --warnings-as-errors` - No compiler warnings
2. `deps.unlock --unused` - Clean unused dependencies
3. `format` - Auto-format code
4. `credo --strict` - Static analysis
5. `dialyzer` - Type checking
6. `test` - All tests pass

Do not commit if any step fails.

## Commit Conventions

This project uses [conventional commits](https://www.conventionalcommits.org/) enforced by commitlint.

**Format:** `type: description` or `type(scope): description`

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`

**Rules:**
- Messages must be **lowercase**
- Max 100 characters in header
- **Never include "Co-authored By"**

**Examples:**
```
feat: add message deduplication support
fix: correct retry backoff calculation
docs: update api reference for fan-out
refactor(delivery): extract retry logic to module
```

## Documentation Requirements

The `docs/` folder contains user-facing documentation. **Update docs when making changes that affect:**

- API endpoints or request/response formats → `docs/api-reference.md`
- Authentication or API keys → `docs/authentication.md`
- Batching behavior → `docs/batching.md`
- Configuration options → `docs/configuration.md`
- Delivery, retries, or timeouts → `docs/delivery.md`
- Core concepts or architecture → `docs/overview.md`
- Webhook consumer guidance → `docs/receiving-webhooks.md`

Keep the main `README.md` in sync for major feature additions.

## Project Structure

```
lib/
├── ricqchet/              # Core business logic (contexts)
│   ├── delivery/          # Message delivery (workers, HTTP client)
│   ├── messages/          # Message context
│   ├── batches/           # Batch message logic
│   ├── dlq/               # Dead letter queue
│   ├── applications/      # Application management
│   ├── api_keys/          # API key management
│   ├── auth/              # JWT authentication
│   ├── tenants/           # Multi-tenancy
│   └── users/             # User management
├── ricqchet.ex            # Public API facade
├── ricqchet_web/          # Phoenix controllers, routes, plugs
│   ├── controllers/       # JSON API controllers
│   ├── plugs/             # Authentication, rate limiting
│   ├── schemas/           # OpenAPI schema definitions
│   └── telemetry.ex       # Telemetry metrics
└── ricqchet_web.ex        # Web module helpers
```

## Key Dependencies

- **Req** - HTTP client (never use httpoison, tesla, or httpc)
- **Oban** - Background job processing
- **OpenApiSpex** - API documentation at `/api/docs`
- **Joken** - JWT token handling
- **Argon2** - Password hashing

## Structured Logging

Use `Logger` with **structured metadata** instead of string interpolation for better observability:

```elixir
require Logger

# GOOD: Structured metadata (preferred)
Logger.info("Message delivered", message_id: message.id, status: status)
Logger.warning("Delivery failed", message_id: message.id, reason: inspect(reason))

# AVOID: String interpolation (harder to query)
Logger.info("Message #{message.id} delivered with status #{status}")
```

**Available metadata** (configured in `config/config.exs`):
- `:request_id` - Auto-populated from `Plug.RequestId`

Add domain-specific metadata when logging in workers and contexts:
- `:message_id`, `:batch_id` - For delivery operations
- `:tenant_id`, `:application_id` - For multi-tenant context
- `:user_id` - For user operations

## Telemetry and Metrics

Custom metrics are defined in `lib/ricqchet_web/telemetry.ex`. The project uses `Telemetry.Metrics` with periodic polling.

**Existing metrics:**
- Phoenix endpoint/router timing
- Ecto query timing (total, decode, query, queue, idle)
- VM memory and run queue lengths

**Adding custom metrics:**

1. Emit telemetry events in your code:
```elixir
:telemetry.execute(
  [:ricqchet, :delivery, :complete],
  %{duration: duration_ms},
  %{status: :success, message_id: message.id}
)
```

2. Add metric definitions in `telemetry.ex`:
```elixir
summary("ricqchet.delivery.complete.duration",
  tags: [:status],
  unit: {:native, :millisecond}
)
```

**Oban telemetry:** Oban emits events automatically for job execution. See [Oban telemetry docs](https://hexdocs.pm/oban/Oban.Telemetry.html).

## Oban Queues

Configured queues (in `config/config.exs`):
- `delivery: 50` - Message delivery jobs
- `dlq_notifications: 10` - Dead letter queue webhook notifications

Workers:
- `Ricqchet.Delivery.Worker` - Single message delivery
- `Ricqchet.Delivery.BatchWorker` - Batch delivery
- `Ricqchet.DLQ.NotificationWorker` - DLQ notifications

## Testing

```bash
mix test                    # Run all tests
mix test path/to/test.exs   # Run specific file
mix test --failed           # Re-run failed tests
```

Uses `Mox` for mocking and `Bypass` for HTTP stubbing.
