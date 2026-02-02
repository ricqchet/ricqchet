defmodule Ricqchet.ActivityEvents do
  @moduledoc """
  Broadcasts activity events for real-time dashboard updates.

  Events are published via PubSub to tenant-specific topics that clients
  can subscribe to through the ActivityChannel WebSocket.

  ## Event Types

  - `message:created` - New message published
  - `message:dispatched` - Message picked up for delivery
  - `message:delivered` - Message successfully delivered
  - `message:retrying` - Delivery failed, scheduled for retry
  - `message:failed` - Message permanently failed

  ## Topic Structure

  Events are broadcast to: `activity:tenant:<tenant_id>`
  """

  alias Phoenix.PubSub

  @pubsub Ricqchet.PubSub

  @doc """
  Broadcasts a message created event.
  """
  def message_created(message) do
    broadcast(message.tenant_id, %{
      type: "message:created",
      entity: "message",
      id: message.id,
      data: %{
        destination_url: message.destination_url,
        status: message.status,
        application_id: message.application_id,
        payload_size_bytes: message.payload_size_bytes
      }
    })
  end

  @doc """
  Broadcasts a message dispatched event.
  """
  def message_dispatched(message) do
    broadcast(message.tenant_id, %{
      type: "message:dispatched",
      entity: "message",
      id: message.id,
      data: %{
        attempt: message.attempts + 1
      }
    })
  end

  @doc """
  Broadcasts a message delivered event.
  """
  def message_delivered(message) do
    broadcast(message.tenant_id, %{
      type: "message:delivered",
      entity: "message",
      id: message.id,
      data: %{
        status_code: message.last_response_status,
        attempts: message.attempts
      }
    })
  end

  @doc """
  Broadcasts a message failed or retrying event.

  ## Options

  - `:will_retry` - Boolean indicating if the message will be retried
  """
  def message_failed(message, opts \\ []) do
    will_retry = Keyword.get(opts, :will_retry, false)
    event_type = if will_retry, do: "message:retrying", else: "message:failed"

    broadcast(message.tenant_id, %{
      type: event_type,
      entity: "message",
      id: message.id,
      data: %{
        attempts: message.attempts,
        error: message.last_error,
        next_retry_at: if(will_retry, do: message.scheduled_at)
      }
    })
  end

  # Private helpers

  defp broadcast(tenant_id, payload) do
    payload = Map.put(payload, :timestamp, DateTime.utc_now())
    topic = "activity:tenant:#{tenant_id}"

    PubSub.broadcast(@pubsub, topic, {:activity_event, payload})
  end
end
