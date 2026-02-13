defmodule Ricqchet.Channels.EventPublisher do
  @moduledoc """
  Publishes events to channel subscribers via PubSub.

  In Phase 1, events are broadcast in-memory only (no DB persistence).
  Phase 2 will add conditional persistence based on namespace configuration.
  """

  alias Phoenix.PubSub

  @pubsub Ricqchet.PubSub

  @doc """
  Publishes an event to a channel.

  Broadcasts the event via PubSub to all subscribers of the channel.
  Returns `{:ok, %{id: event_id}}` with a generated event ID.

  ## Options

  - `:socket_id` - Socket ID to exclude from broadcast (sender exclusion)
  """
  @spec publish(String.t(), String.t(), String.t(), term(), keyword()) ::
          {:ok, %{id: String.t()}}
  def publish(application_id, channel, event_name, data, opts \\ []) do
    event_id = Ecto.UUID.generate()
    socket_id = Keyword.get(opts, :socket_id)

    payload = %{
      id: event_id,
      event: event_name,
      data: data,
      channel: channel,
      socket_id: socket_id
    }

    topic = "channels:app:#{application_id}:#{channel}"
    PubSub.broadcast(@pubsub, topic, {:channel_event, payload})

    {:ok, %{id: event_id}}
  end
end
