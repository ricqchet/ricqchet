# Ricqchet

Elixir client for [Ricqchet](https://github.com/doomspork/ricqchet) HTTP message queue service.

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

## Testing

The library includes test helpers for testing code that uses Ricqchet clients.

### Setup

Configure the test adapter in `config/test.exs`:

```elixir
config :ricqchet, adapter: Ricqchet.Adapters.Test
```

### Assertions

Use `Ricqchet.Testing` for a clean assertion API:

```elixir
defmodule MyApp.QueueTest do
  use ExUnit.Case, async: true
  import Ricqchet.Testing

  test "publishes order created event" do
    {:ok, %{message_id: id}} = MyApp.Queue.publish(%{event: "order.created", id: 123})

    assert is_binary(id)
    assert_published destination: "https://myapp.com/webhook",
                     payload: %{event: "order.created", id: 123}
  end

  test "publishes with delay option" do
    MyApp.Queue.publish(%{event: "reminder"}, delay: "1h")

    assert_published delay: "1h"
  end

  test "refutes publish when nothing sent" do
    refute_published()
  end

  test "fan-out to multiple destinations" do
    dests = ["https://a.example.com", "https://b.example.com"]
    {:ok, _} = MyApp.Queue.publish_fan_out(dests, %{event: "broadcast"})

    assert_fan_out dests
  end
end
```

### Stubbing Responses

Control adapter responses for error handling tests:

```elixir
test "handles rate limiting" do
  stub_response(:publish, {:error, %Ricqchet.Error{type: :rate_limited}})

  assert {:error, %{type: :rate_limited}} = MyApp.Queue.publish(%{event: "test"})
end

test "handles not found" do
  stub_response(:get_message, {:error, :not_found}, message_id: "nonexistent")

  assert {:error, :not_found} = MyApp.Queue.get_message("nonexistent")
end
```

### Testing GenServers and Spawned Processes

For integration tests with spawned processes, use global mode:

```elixir
defmodule MyApp.WorkerTest do
  use ExUnit.Case, async: false  # Must be false for global mode
  import Ricqchet.Testing

  setup do
    set_ricqchet_global()
    :ok
  end

  test "worker publishes on tick" do
    {:ok, worker} = MyApp.Worker.start_link()

    send(worker, :tick)

    assert_published destination: "https://example.com"
  end
end
```

### Using Mox (Advanced)

For explicit mock expectations, use Mox with the adapter behaviour:

```elixir
# In test/test_helper.exs
Mox.defmock(Ricqchet.MockAdapter, for: Ricqchet.Client.Adapter)

# In config/test.exs
config :ricqchet, adapter: Ricqchet.MockAdapter

# In your test
defmodule MyApp.QueueMoxTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  test "with explicit expectations" do
    expect(Ricqchet.MockAdapter, :publish, fn _config, dest, payload, opts ->
      assert dest == "https://myapp.com/webhook"
      assert payload.event == "order.created"
      assert opts[:delay] == "5m"
      {:ok, %{message_id: "custom-id-123"}}
    end)

    assert {:ok, %{message_id: "custom-id-123"}} =
             MyApp.Queue.publish(%{event: "order.created"}, delay: "5m")
  end
end
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
