defmodule Ricqchet.Channels.EventPublisher do
  @moduledoc """
  Publishes events to channel subscribers via PubSub.

  When a matching namespace has `history_enabled`, events are persisted to the
  database with a monotonically increasing sequence number for reliable client
  reconnect recovery. Events are always broadcast regardless of persistence.
  """

  require Logger

  alias Phoenix.PubSub
  alias Ricqchet.Channels.ChannelEvent
  alias Ricqchet.Channels.NamespaceConfig
  alias Ricqchet.Repo

  import Ecto.Query

  @pubsub Ricqchet.PubSub

  @doc """
  Publishes an event to a channel.

  Broadcasts the event via PubSub to all subscribers of the channel.
  If the channel's namespace has history enabled, the event is also
  persisted to the database.

  Returns `{:ok, %{id: event_id}}` with a generated or persisted event ID.

  ## Options

  - `:socket_id` - Socket ID to exclude from broadcast (sender exclusion)
  - `:tenant_id` - Tenant ID for event persistence
  - `:user_id` - User ID for event persistence
  """
  @spec publish(String.t(), String.t(), String.t(), term(), keyword()) ::
          {:ok, %{id: String.t()}} | {:error, :event_too_large}
  def publish(application_id, channel, event_name, data, opts \\ []) do
    socket_id = Keyword.get(opts, :socket_id)
    tenant_id = Keyword.get(opts, :tenant_id)
    user_id = Keyword.get(opts, :user_id)

    encoded_data = Jason.encode!(data)

    case check_event_size(application_id, channel, encoded_data) do
      :ok ->
        do_publish(application_id, channel, event_name, data, encoded_data,
          socket_id: socket_id,
          tenant_id: tenant_id,
          user_id: user_id
        )

      {:error, :event_too_large} = error ->
        error
    end
  end

  defp do_publish(application_id, channel, event_name, data, encoded_data, opts) do
    socket_id = Keyword.get(opts, :socket_id)
    tenant_id = Keyword.get(opts, :tenant_id)
    user_id = Keyword.get(opts, :user_id)

    {event_id, sequence} =
      case maybe_persist(
             application_id,
             tenant_id,
             channel,
             event_name,
             encoded_data,
             socket_id,
             user_id
           ) do
        {:ok, id, seq} -> {id, seq}
        :skip -> {Ecto.UUID.generate(), nil}
      end

    payload = %{
      id: event_id,
      event: event_name,
      data: data,
      channel: channel,
      socket_id: socket_id,
      sequence: sequence
    }

    topic = "channels:app:#{application_id}:#{channel}"
    PubSub.broadcast(@pubsub, topic, {:channel_event, payload})

    :telemetry.execute(
      [:ricqchet, :channels, :event, :published],
      %{data_size: byte_size(encoded_data)},
      %{application_id: application_id, channel: channel, event: event_name}
    )

    {:ok, %{id: event_id}}
  end

  defp check_event_size(application_id, channel, encoded_data) do
    case NamespaceConfig.get_namespace_for_channel(application_id, channel) do
      {:ok, %{max_event_size_bytes: max}} when is_integer(max) ->
        if byte_size(encoded_data) > max, do: {:error, :event_too_large}, else: :ok

      _ ->
        :ok
    end
  end

  defp maybe_persist(application_id, tenant_id, channel, event_name, data, socket_id, user_id) do
    case NamespaceConfig.get_namespace_for_channel(application_id, channel) do
      {:ok, %{history_enabled: true} = namespace} ->
        persist_event(
          application_id,
          tenant_id,
          channel,
          event_name,
          data,
          socket_id,
          user_id,
          namespace
        )

      _ ->
        :skip
    end
  end

  defp persist_event(
         application_id,
         tenant_id,
         channel,
         event_name,
         encoded_data,
         socket_id,
         user_id,
         namespace
       ) do
    attrs = %{
      channel: channel,
      event_name: event_name,
      data: encoded_data,
      data_size_bytes: byte_size(encoded_data),
      user_id: user_id,
      socket_id: socket_id
    }

    changeset =
      ChannelEvent.changeset(
        %ChannelEvent{application_id: application_id, tenant_id: tenant_id},
        attrs
      )

    case Repo.insert(changeset) do
      {:ok, event} ->
        trim_history(application_id, channel, namespace.history_max_events)
        {:ok, event.id, event.sequence}

      {:error, reason} ->
        Logger.error("Failed to persist channel event",
          application_id: application_id,
          channel: channel,
          reason: inspect(reason)
        )

        :skip
    end
  end

  defp trim_history(_application_id, _channel, nil), do: :ok

  defp trim_history(application_id, channel, max_events) do
    subquery =
      from(e in ChannelEvent,
        where: e.application_id == ^application_id and e.channel == ^channel,
        order_by: [desc: :sequence],
        offset: ^max_events,
        select: e.id
      )

    delete_query = from(e in ChannelEvent, where: e.id in subquery(subquery))
    Repo.delete_all(delete_query)

    :ok
  end
end
