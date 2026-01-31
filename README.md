# Ricqchet

HTTP message queuing service with guaranteed delivery, similar to [Upstash QStash](https://upstash.com/docs/qstash/overall/getstarted).

Ricqchet allows serverless functions to POST events that are queued and delivered to destination URLs with automatic retries and exponential backoff.

## Features

- **Guaranteed delivery** with automatic retries and exponential backoff
- **Multi-tenant** architecture with application-scoped API keys
- **Fan-out** to broadcast messages to multiple destinations
- **Deduplication** to prevent duplicate message processing
- **Delayed delivery** with configurable scheduling (up to 7 days)
- **Message batching** for efficient bulk delivery
- **Header forwarding** to destination endpoints
- **Message status tracking** with detailed attempt history
- **OpenAPI documentation** at `/api/docs`

## Tech Stack

- Elixir 1.18+ / OTP 27+
- Phoenix 1.8+ (API only)
- PostgreSQL 15+
- Oban for reliable job processing

## Getting Started

### Prerequisites

- Erlang 27+
- Elixir 1.18+
- PostgreSQL 15+

If using [mise](https://mise.jdx.dev/), run `mise install` to set up the correct versions.

### Setup

```bash
mix setup
mix phx.server
```

### Create Credentials

```elixir
# In iex -S mix
alias Ricqchet.{Tenants, Applications, ApiKeys}

# 1. Create a tenant (organization)
{:ok, tenant} = Tenants.create_tenant(%{name: "My Organization"})

# 2. Create an application
{:ok, app} = Applications.create_application(tenant, %{name: "My App"})

# 3. Create an API key - save this, it's only shown once!
{:ok, api_key} = ApiKeys.create_api_key(app, %{name: "Production"})
IO.puts("API Key: #{api_key.api_key}")
```

### Publish a Message

```bash
curl -X POST "http://localhost:4000/v1/publish" \
  -H "Authorization: Bearer <your_api_key>" \
  -H "Content-Type: application/json" \
  -H "Ricqchet-Destination: https://httpbin.org/post" \
  -d '{"hello": "world"}'
```

## Development

```bash
mix test              # Run tests
mix format            # Format code
mix credo --strict    # Static analysis
mix dialyzer          # Type checking
```

## Documentation

- [API Reference](docs/api-reference.md) - Endpoints, headers, and examples
- [Authentication](docs/authentication.md) - Multi-tenant setup and API keys
- [Batching](docs/batching.md) - Message batching configuration
- [Delivery](docs/delivery.md) - Retry behavior and delivered headers
- [Configuration](docs/configuration.md) - Application configuration

Interactive API docs available at `/api/docs` when the server is running.

## License

MIT
