# Configuration

## Oban (Job Queue)

Configure Oban for reliable message delivery in `config/config.exs`:

```elixir
config :ricqchet, Oban,
  repo: Ricqchet.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [delivery: 50]  # 50 concurrent delivery workers
```

### Queue Concurrency

The `delivery` queue controls how many messages can be delivered simultaneously. Adjust based on your infrastructure:

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

The dispatcher polls for pending messages. Configure in your application:

```elixir
# lib/ricqchet/application.ex
children = [
  # ... other children
  {Ricqchet.Dispatcher, poll_interval: 100}  # milliseconds
]
```

Default poll interval is 100ms. Increase for lower CPU usage, decrease for faster dispatch.

## Batch Dispatcher

Similar to the message dispatcher, but for batches:

```elixir
{Ricqchet.BatchDispatcher, poll_interval: 100}
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

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | - |
| `POOL_SIZE` | Database connection pool size | 10 |
| `SECRET_KEY_BASE` | Phoenix secret key | - |
| `PHX_HOST` | Application host for URLs | localhost |
| `PORT` | HTTP server port | 4000 |

## Development Dashboard

In development, a Phoenix LiveDashboard is available at `/dev/dashboard`:

```elixir
# config/dev.exs
config :ricqchet, dev_routes: true
```

Access requires basic auth configured in the router.
