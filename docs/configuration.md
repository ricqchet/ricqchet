# Configuration

## Oban (Job Queue)

Configure Oban for reliable message delivery in `config/config.exs`:

```elixir
config :ricqchet, Oban,
  repo: Ricqchet.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [delivery: 50, dlq_notifications: 10]
```

### Queue Concurrency

| Queue | Purpose | Default |
|-------|---------|---------|
| `delivery` | Message/batch delivery to destinations | 50 |
| `dlq_notifications` | DLQ webhook notifications | 10 |

Adjust based on your infrastructure:

```elixir
# Low traffic
queues: [delivery: 10]

# High traffic
queues: [delivery: 100]
```

### Pruning

The `Oban.Plugins.Pruner` automatically removes completed jobs. Configure retention:

```elixir
plugins: [
  {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}  # 7 days
]
```

## Dispatcher

The dispatcher polls for pending messages and enqueues them for delivery. Configure via application config:

```elixir
# config/config.exs
config :ricqchet, Ricqchet.Dispatcher,
  poll_interval_ms: 100,        # milliseconds between polls (default: 100)
  max_messages_per_cycle: 100   # max messages to claim per poll cycle (default: 100)

# To disable the dispatcher (e.g., in tests)
config :ricqchet, :dispatcher_enabled, false
```

Increase `poll_interval_ms` for lower CPU usage, decrease for faster dispatch.

## Batch Dispatcher

The batch dispatcher polls for ready batches and enqueues them for delivery:

```elixir
# config/config.exs
config :ricqchet, Ricqchet.BatchDispatcher,
  poll_interval_ms: 100,        # milliseconds between polls (default: 100)
  max_batches_per_cycle: 50     # max batches to claim per poll cycle (default: 50)

# To disable the batch dispatcher
config :ricqchet, :batch_dispatcher_enabled, false
```

## Database

### PostgreSQL Connection

```elixir
# config/dev.exs
config :ricqchet, Ricqchet.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ricqchet_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
```

### Production Configuration

```elixir
# config/runtime.exs
config :ricqchet, Ricqchet.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true
```

## HTTP Client

The HTTP client (Req) is configured with:

- 10 second connection timeout
- 30 second receive timeout
- Automatic redirect following (up to 5 redirects)
- Compressed responses accepted

These values are currently hardcoded in `Ricqchet.Delivery.HttpClient`.

## CORS

CORS is configured to allow cross-origin requests from web dashboards and frontends.

### Development

In development, localhost origins are allowed by default:

```elixir
# config/config.exs
config :ricqchet, :cors,
  allowed_origins: ["http://localhost:3000", "http://localhost:4000"],
  allow_credentials: true,
  max_age: 86_400
```

### Production

In production, set allowed origins via environment variable:

```bash
# Comma-separated list of allowed origins
CORS_ALLOWED_ORIGINS=https://app.example.com,https://dashboard.example.com
```

### CORS Headers

The following headers are allowed:
- `content-type`
- `authorization`
- `x-api-key`
- `x-request-id`

Allowed methods: GET, POST, PUT, PATCH, DELETE, OPTIONS

Credentials (cookies, authorization headers) are supported for authenticated requests.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | - |
| `POOL_SIZE` | Database connection pool size | 10 |
| `SECRET_KEY_BASE` | Phoenix secret key | - |
| `PHX_HOST` | Application host for URLs | localhost |
| `PORT` | HTTP server port | 4000 |
| `CORS_ALLOWED_ORIGINS` | Comma-separated list of allowed CORS origins | http://localhost:3000, http://localhost:4000 |

## Development Dashboard

In development, a Phoenix LiveDashboard is available at `/dev/dashboard`:

```elixir
# config/dev.exs
config :ricqchet, dev_routes: true
```

Access requires basic auth configured in the router.
