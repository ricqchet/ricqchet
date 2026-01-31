# Ricqchet

Elixir client for [Ricqchet](https://github.com/doomspork/tacoma) HTTP message queue service.

## Installation

Add `ricqchet` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ricqchet, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Define a Client

```elixir
defmodule MyApp.Queue do
  use Ricqchet.Client,
    base_url: "https://your-ricqchet.fly.dev",
    api_key: {:system, "RICQCHET_API_KEY"},
    destination: "https://myapp.com/webhook"
end
```

### Publish Messages

```elixir
# Simple publish
{:ok, %{message_id: id}} = MyApp.Queue.publish(%{event: "order.created", id: 123})

# With delay
{:ok, %{message_id: id}} = MyApp.Queue.publish(%{event: "reminder"}, delay: "5m")

# With deduplication
{:ok, %{message_id: id}} = MyApp.Queue.publish(
  %{event: "process"},
  dedup_key: "order-123",
  dedup_ttl: 3600
)

# Publish to explicit destination
{:ok, %{message_id: id}} = MyApp.Queue.publish_to(
  "https://other.example.com/webhook",
  %{event: "notification"}
)

# Fan-out to multiple destinations
{:ok, %{message_ids: ids}} = MyApp.Queue.publish_fan_out(
  ["https://a.example.com", "https://b.example.com"],
  %{event: "broadcast"}
)
```

### Message Management

```elixir
# Get message status
{:ok, message} = MyApp.Queue.get_message("550e8400-e29b-41d4-a716-446655440000")

# Cancel a pending message
{:ok, %{cancelled: true}} = MyApp.Queue.cancel_message("550e8400-...")
```

## Webhook Verification

Verify incoming webhooks from Ricqchet using HMAC signatures.

### Define a Verification Module

```elixir
defmodule MyApp.RicqchetWebhook do
  use Ricqchet.Verification,
    signing_secret: {:system, "RICQCHET_SIGNING_SECRET"}
end
```

### Verify in Your Controller

```elixir
defmodule MyAppWeb.WebhookController do
  use MyAppWeb, :controller

  # Important: Cache the raw body in assigns for verification
  plug :cache_raw_body when action in [:webhook]

  def webhook(conn, params) do
    case MyApp.RicqchetWebhook.verify(conn) do
      {:ok, %{message_id: message_id, attempt: attempt}} ->
        # Process the webhook
        handle_event(params)
        send_resp(conn, 200, "OK")

      {:error, :invalid_signature} ->
        send_resp(conn, 401, "Invalid signature")

      {:error, :signature_expired} ->
        send_resp(conn, 401, "Signature expired")
    end
  end

  defp cache_raw_body(conn, _opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    conn
    |> assign(:raw_body, body)
    |> Plug.Conn.put_private(:raw_body, body)
  end
end
```

### Standalone Verification

```elixir
# If you have the raw body and headers separately
Ricqchet.Verification.verify_payload(
  signature_header,
  raw_body,
  signing_secret,
  max_age: 300
)
```

## Configuration Options

### Client Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `base_url` | string | yes | Ricqchet server URL |
| `api_key` | string or `{:system, "ENV"}` | yes | API key |
| `destination` | string | no | Default destination URL |
| `timeout` | integer | no | HTTP timeout in ms (default: 30000) |

### Publish Options

| Option | Type | Description |
|--------|------|-------------|
| `delay` | string | Delay delivery (e.g., "30s", "5m", "1h") |
| `dedup_key` | string | Deduplication key |
| `dedup_ttl` | integer | Deduplication TTL in seconds |
| `retries` | integer | Max retry attempts |
| `batch_key` | string | Batch key for grouping |
| `batch_size` | integer | Max batch size |
| `batch_timeout` | integer | Batch timeout in seconds |
| `forward_headers` | map | Headers to forward |
| `content_type` | string | Content-Type header |

## License

MIT
