defmodule RicqchetWeb.Channels.PubsubChannel do
  @moduledoc """
  Phoenix Channel for real-time channel subscriptions.

  Handles join/leave for public, private, and presence channels with
  tenant isolation. Events published via the REST API are broadcast
  through PubSub and pushed to connected clients.

  ## Topic format

      channels:app:<application_id>:<channel_name>

  ## Channel types (by name prefix)

  - No prefix: public channel (open join)
  - `private-`: private channel (requires auth endpoint approval)
  - `presence-`: presence channel (requires auth endpoint approval)
  """

  use RicqchetWeb, :channel

  require Logger

  alias Ricqchet.Channels
  alias Ricqchet.Channels.Auth
  alias Ricqchet.Channels.ClientEventRateLimiter
  alias Ricqchet.Channels.History
  alias Ricqchet.Channels.NamespaceConfig
  alias Ricqchet.Channels.SubscriberTracker
  alias RicqchetWeb.Channels.ChannelSocket
  alias RicqchetWeb.Channels.Presence

  intercept ["presence_diff"]

  @impl Phoenix.Channel
  def join("channels:app:" <> rest, params, socket) do
    case parse_topic(rest) do
      {:ok, app_id, channel_name} ->
        authorize_and_join(app_id, channel_name, params, socket)

      :error ->
        {:error, %{reason: "invalid_topic"}}
    end
  end

  def join(_topic, _params, _socket) do
    {:error, %{reason: "invalid_topic"}}
  end

  @impl Phoenix.Channel
  def handle_info({:channel_event, payload}, socket) do
    if payload[:socket_id] && payload[:socket_id] == ChannelSocket.id(socket) do
      {:noreply, socket}
    else
      event_data = %{data: payload.data, channel: payload.channel}

      event_data =
        if payload[:sequence],
          do: Map.put(event_data, :sequence, payload.sequence),
          else: event_data

      push(socket, payload.event, event_data)
      {:noreply, socket}
    end
  end

  def handle_info({:recover_events, app_id, channel_name, last_event_id}, socket) do
    case History.get_events_since(app_id, channel_name, last_event_id) do
      {:ok, events} ->
        Enum.each(events, fn event ->
          push(socket, event.event_name, %{
            data: decode_event_data(event.data),
            channel: event.channel,
            sequence: event.sequence
          })
        end)

      {:error, :event_not_found} ->
        push(socket, "ricqchet:recovery_failed", %{
          reason: "event_not_found",
          last_event_id: last_event_id,
          channel: channel_name
        })
    end

    {:noreply, socket}
  end

  def handle_info({:maybe_send_cached_event, app_id, channel_name}, socket) do
    with {:ok, %{cache_enabled: true}} <-
           NamespaceConfig.get_namespace_for_channel(app_id, channel_name),
         %{} = event <- Channels.get_last_event(app_id, channel_name) do
      push(socket, "ricqchet:cached_event", %{
        data: decode_event_data(event.data),
        channel: event.channel,
        event: event.event_name,
        sequence: event.sequence,
        id: event.id
      })
    end

    {:noreply, socket}
  end

  def handle_info(:after_join_presence, socket) do
    user_id = socket.assigns.user_id
    user_info = socket.assigns.user_info

    {:ok, _ref} =
      Presence.track(socket, user_id, %{
        user_info: user_info,
        joined_at: System.system_time(:second)
      })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  @impl Phoenix.Channel
  def handle_out("presence_diff", diff, socket) do
    push(socket, "presence_diff", diff)
    {:noreply, socket}
  end

  @impl Phoenix.Channel
  def handle_in("client-" <> _ = event, payload, socket) do
    channel_name = socket.assigns.channel_name
    app_id = socket.assigns.application_id
    user_id = socket.assigns.user_id

    with :ok <- validate_client_channel(channel_name),
         :ok <- check_client_rate(app_id, user_id, channel_name) do
      broadcast_from!(socket, event, %{
        data: payload,
        channel: channel_name,
        user_id: user_id
      })

      {:reply, :ok, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "invalid_event"}}, socket}
  end

  @impl Phoenix.Channel
  def terminate(_reason, socket) do
    case parse_topic_from_socket(socket) do
      {:ok, app_id, channel_name} ->
        SubscriberTracker.track_leave(app_id, channel_name)

      :error ->
        :ok
    end

    :ok
  end

  defp authorize_and_join(app_id, channel_name, params, socket) do
    with :ok <- verify_app_ownership(app_id, socket),
         :ok <- validate_name(channel_name) do
      last_event_id = Map.get(params, "last_event_id")

      case channel_type(channel_name) do
        :public -> do_join(app_id, channel_name, last_event_id, socket)
        _authenticated -> join_with_auth(app_id, channel_name, last_event_id, socket)
      end
    end
  end

  defp verify_app_ownership(app_id, socket) do
    if app_id == socket.assigns.application_id,
      do: :ok,
      else: {:error, %{reason: "unauthorized"}}
  end

  defp validate_name(channel_name) do
    case Channels.validate_channel_name(channel_name) do
      :ok -> :ok
      {:error, reason} -> {:error, %{reason: reason}}
    end
  end

  defp join_with_auth(app_id, channel_name, last_event_id, socket) do
    application = socket.assigns.application
    user_id = socket.assigns.user_id
    socket_id = ChannelSocket.id(socket)

    case Auth.authorize(application, channel_name, user_id, socket_id) do
      {:ok, _auth_data} ->
        do_join(app_id, channel_name, last_event_id, socket)

      {:error, :forbidden} ->
        {:error, %{reason: "forbidden"}}

      {:error, :no_auth_endpoint} ->
        {:error, %{reason: "auth_endpoint_not_configured"}}

      {:error, :auth_unavailable} ->
        {:error, %{reason: "auth_unavailable"}}
    end
  end

  defp do_join(app_id, channel_name, last_event_id, socket) do
    topic = "channels:app:#{app_id}:#{channel_name}"
    Phoenix.PubSub.subscribe(Ricqchet.PubSub, topic)
    SubscriberTracker.track_join(app_id, channel_name)

    if last_event_id do
      send(self(), {:recover_events, app_id, channel_name, last_event_id})
    else
      send(self(), {:maybe_send_cached_event, app_id, channel_name})
    end

    if channel_type(channel_name) == :presence do
      send(self(), :after_join_presence)
    end

    socket = assign(socket, :channel_name, channel_name)
    {:ok, socket}
  end

  defp validate_client_channel("private-" <> _), do: :ok
  defp validate_client_channel("presence-" <> _), do: :ok
  defp validate_client_channel(_), do: {:error, "client_events_not_allowed"}

  defp check_client_rate(app_id, user_id, channel_name) do
    limit =
      case NamespaceConfig.get_namespace_for_channel(app_id, channel_name) do
        {:ok, %{max_client_events_per_second: limit}} when is_integer(limit) -> limit
        _ -> 10
      end

    case ClientEventRateLimiter.check_rate(app_id, user_id, limit) do
      :ok -> :ok
      :rate_limited -> {:error, "rate_limited"}
    end
  end

  defp decode_event_data(nil), do: nil

  defp decode_event_data(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> decoded
      _ -> data
    end
  end

  defp decode_event_data(data), do: data

  defp channel_type("private-" <> _), do: :private
  defp channel_type("presence-" <> _), do: :presence
  defp channel_type(_), do: :public

  defp parse_topic(rest) do
    case String.split(rest, ":", parts: 2) do
      [app_id, channel_name] when app_id != "" and channel_name != "" ->
        {:ok, app_id, channel_name}

      _ ->
        :error
    end
  end

  defp parse_topic_from_socket(socket) do
    case socket.topic do
      "channels:app:" <> rest -> parse_topic(rest)
      _ -> :error
    end
  end
end
