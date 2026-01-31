# Ricqchet

HTTP message queuing with guaranteed delivery.

## Packages

| Package | Description |
|---------|-------------|
| [server](./server) | Ricqchet server (Elixir/Phoenix) |
| [elixir-client](./clients/elixir) | Elixir client library |
| [typescript-client](./clients/typescript) | TypeScript client library |

## Overview

Ricqchet allows serverless functions to POST events that are queued and delivered to destination URLs with automatic retries and exponential backoff. Key features:

- **Guaranteed delivery** with configurable retries
- **Delayed delivery** with scheduling support
- **Deduplication** to prevent duplicate processing
- **Batching** to group messages efficiently
- **Fan-out** to broadcast to multiple destinations
- **HMAC signatures** for webhook verification

## Quick Start

### Server

```bash
cd server
mix setup
mix phx.server
```

### Elixir Client

```elixir
defmodule MyApp.Queue do
  use Ricqchet.Client,
    base_url: "https://your-ricqchet.fly.dev",
    api_key: {:system, "RICQCHET_API_KEY"},
    destination: "https://webhook.example.com"
end

MyApp.Queue.publish(%{event: "order.created", id: 123})
```

### TypeScript Client

```typescript
import { RicqchetClient } from '@ricqchet/client';

const client = new RicqchetClient({
  baseUrl: 'https://your-ricqchet.fly.dev',
  apiKey: process.env.RICQCHET_API_KEY!
});

await client.publish('https://webhook.example.com', { event: 'order.created', id: 123 });
```

## Development

### Prerequisites

- Erlang 27+ / Elixir 1.18+
- Node.js 20+
- PostgreSQL 15+

Use [mise](https://mise.jdx.dev/) to install the correct tool versions: `mise install`

### Running Tests

```bash
# Server
cd server && mix test

# Elixir client
cd clients/elixir && mix test

# TypeScript client
cd clients/typescript && npm test
```

### Code Quality

```bash
# Server
cd server && mix format && mix credo --strict && mix dialyzer

# Elixir client
cd clients/elixir && mix format && mix credo --strict

# TypeScript client
cd clients/typescript && npm run lint && npm run format:check
```

## Documentation

- [Overview](docs/overview.md) - What Ricqchet is and how it works
- [API Reference](docs/api-reference.md) - Endpoints, headers, and examples
- [Authentication](docs/authentication.md) - Multi-tenant setup and API keys
- [Batching](docs/batching.md) - Message batching configuration
- [Delivery](docs/delivery.md) - Retry behavior and delivered headers
- [Configuration](docs/configuration.md) - Application configuration
- [Receiving Webhooks](docs/receiving-webhooks.md) - Guide for webhook consumers

Interactive API docs available at `/api/docs` when the server is running.

## Commit Conventions

This repo uses [Conventional Commits](https://www.conventionalcommits.org/) with component scopes:

```
feat(server): add webhook signature verification
feat(elixir-client): add batch timeout validation
fix(typescript-client): handle undefined headers
```

## License

MIT
