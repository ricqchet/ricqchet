defmodule Ricqchet do
  @moduledoc """
  Elixir client for Ricqchet HTTP message queue service.

  Ricqchet provides reliable HTTP message delivery with:
  - Automatic retries with exponential backoff
  - Message deduplication
  - Batching for high-throughput scenarios
  - Fan-out to multiple destinations
  - HMAC signature verification for webhooks

  ## Quick Start

  Define a client module:

      defmodule MyApp.Queue do
        use Ricqchet.Client,
          base_url: "https://your-ricqchet.fly.dev",
          api_key: {:system, "RICQCHET_API_KEY"},
          destination: "https://myapp.com/webhook"
      end

  Publish messages:

      {:ok, %{message_id: id}} = MyApp.Queue.publish(%{event: "order.created"})

  ## Webhook Verification

  Verify incoming webhooks:

      defmodule MyApp.Verification do
        use Ricqchet.Verification,
          signing_secret: {:system, "RICQCHET_SIGNING_SECRET"}
      end

      case MyApp.Verification.verify(conn) do
        {:ok, metadata} -> handle_webhook(conn)
        {:error, reason} -> send_resp(conn, 401, "Invalid signature")
      end
  """
end
