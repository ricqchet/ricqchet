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
    broadcast(message.tenant_id, serialize(message))
  end

  @doc """
  Broadcasts a message dispatched event.
  """
  def message_dispatched(message) do
    broadcast(message.tenant_id, serialize(message))
  end

  @doc """
  Broadcasts a message delivered event.
  """
  def message_delivered(message) do
    broadcast(message.tenant_id, serialize(message))
  end

  @doc """
  Broadcasts a message failed or retrying event.

  ## Options

  - `:will_retry` - Boolean indicating if the message will be retried
  """
  def message_failed(message, opts \\ []) do
    will_retry = Keyword.get(opts, :will_retry, false)
    status = if will_retry, do: "retrying", else: message.status

    payload =
      message
      |> serialize()
      |> Map.put(:status, status)

    broadcast(message.tenant_id, payload)
  end

  # Private helpers

  defp serialize(message) do
    %{
      id: message.id,
      destination_url: message.destination_url,
      status: message.status,
      attempts: message.attempts,
      last_error: message.last_error,
      last_response_status: message.last_response_status,
      payload_size_bytes: message.payload_size_bytes,
      application_id: message.application_id,
      created_at: message.inserted_at,
      completed_at: message.completed_at
    }
  end

  defp broadcast(tenant_id, payload) do
    topic = "activity:tenant:#{tenant_id}"

    PubSub.broadcast(@pubsub, topic, {:activity_event, payload})
  end
end
