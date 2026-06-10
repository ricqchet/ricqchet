defmodule RicqchetWeb.Channels.PubsubChannel do
  @moduledoc """
  Phoenix Channel for real-time channel subscriptions.

  Handles join/leave for public, private, and presence channels with
  tenant isolation. Events published via the REST API are broadcast
  through PubSub and pushed to connected clients.

  ## Topic format

  Clients join with the **bare channel name** as the topic — e.g. `chat-room`,
  `private-orders`, `presence-lobby`, or a hierarchical name like `orders.us.west`.
  The application is derived from the authenticated socket
  (`socket.assigns.application_id`), so clients never embed it in the topic.

  Internally, server-published events and presence are namespaced on the PubSub topic

      channels:app:<application_id>:<channel_name>

  which keeps tenants isolated even when two applications use the same channel
  name. Clients never see this internal topic.

  ## Channel types (by name prefix)

  - No prefix: public channel (open join)
  - `private-`: private channel (requires auth endpoint approval)
  - `presence-`: presence channel (requires auth endpoint approval)
  """

  use RicqchetWeb, :channel

  require Logger

  alias Phoenix.Socket.Broadcast
  alias Ricqchet.Channels
  alias Ricqchet.Channels.Auth
  alias Ricqchet.Channels.ClientEventRateLimiter
  alias Ricqchet.Channels.History
  alias Ricqchet.Channels.NamespaceConfig
  alias Ricqchet.Channels.SubscriberTracker
  alias Ricqchet.Channels.WebhookNotifier
  alias RicqchetWeb.Channels.Presence

  @impl Phoenix.Channel
  def join(channel_name, params, socket) do
    case Channels.validate_channel_name(channel_name) do
      :ok ->
        authorize_and_join(channel_name, params, socket)

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  @impl Phoenix.Channel
  def handle_info({:channel_event, payload}, socket) do
    if payload[:socket_id] && payload[:socket_id] == socket.assigns.socket_id do
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

        :telemetry.execute(
          [:ricqchet, :channels, :recovery],
          %{events_count: length(events)},
          %{application_id: app_id, status: :ok}
        )

      {:error, :event_not_found} ->
        push(socket, "ricqchet:recovery_failed", %{
          reason: "event_not_found",
          last_event_id: last_event_id,
          channel: channel_name
        })

        :telemetry.execute(
          [:ricqchet, :channels, :recovery],
          %{events_count: 0},
          %{application_id: app_id, status: :failed}
        )
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
    topic = internal_topic(socket.assigns.application_id, socket.assigns.channel_name)

    {:ok, _ref} =
      Presence.track(self(), topic, user_id, %{
        user_info: user_info,
        joined_at: System.system_time(:second)
      })

    push(socket, "presence_state", Presence.list(topic))

    :telemetry.execute(
      [:ricqchet, :channels, :presence, :track],
      %{count: 1},
      %{application_id: socket.assigns.application_id}
    )

    enqueue_webhook("member:added", socket.assigns.application_id, socket.assigns.channel_name,
      user_id: user_id,
      user_info: user_info
    )

    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "presence_diff", payload: diff}, socket) do
    push(socket, "presence_diff", diff)
    {:noreply, socket}
  end

  def handle_info({:client_event, event, payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  # Defensive catch-all: the channel subscribes to the internal PubSub topic, so an
  # unexpected message there must not crash the process (which would fire spurious
  # leave/vacated side effects via terminate/2).
  def handle_info(msg, socket) do
    Logger.debug("PubsubChannel ignoring unexpected message: #{inspect(msg)}")
    {:noreply, socket}
  end

  @impl Phoenix.Channel
  def handle_in("client-" <> _ = event, payload, socket) do
    channel_name = socket.assigns.channel_name
    app_id = socket.assigns.application_id
    user_id = socket.assigns.user_id
    connection_id = socket.assigns.connection_id

    with :ok <- validate_client_channel(channel_name),
         :ok <- check_client_rate(app_id, connection_id, channel_name) do
      Phoenix.PubSub.broadcast_from(
        Ricqchet.PubSub,
        self(),
        internal_topic(app_id, channel_name),
        {:client_event, event, %{data: payload, channel: channel_name, user_id: user_id}}
      )

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
    app_id = socket.assigns[:application_id]
    channel_name = socket.assigns[:channel_name]

    # channel_name is only assigned after a successful join, so its presence
    # means this connection actually subscribed to a channel. Connection-count
    # accounting is handled per-socket by ConnectionTracker (which monitors the
    # socket process), not here — terminate/2 fires once per channel, not per socket.
    if app_id && channel_name do
      if SubscriberTracker.track_leave(app_id, channel_name) == :last_subscriber do
        enqueue_webhook("channel:vacated", app_id, channel_name)
      end

      if channel_type(channel_name) == :presence do
        enqueue_webhook("member:removed", app_id, channel_name,
          user_id: socket.assigns[:user_id],
          user_info: socket.assigns[:user_info]
        )
      end
    end

    :ok
  end

  defp authorize_and_join(channel_name, params, socket) do
    app_id = socket.assigns.application_id
    last_event_id = Map.get(params, "last_event_id")

    case channel_type(channel_name) do
      :public -> do_join(app_id, channel_name, last_event_id, socket)
      _authenticated -> join_with_auth(app_id, channel_name, last_event_id, socket)
    end
  end

  defp join_with_auth(app_id, channel_name, last_event_id, socket) do
    application = socket.assigns.application
    user_id = socket.assigns.user_id
    socket_id = socket.assigns.socket_id

    case Auth.authorize(application, channel_name, user_id, socket_id) do
      {:ok, auth_data} ->
        socket = bind_identity(socket, auth_data)
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
    Phoenix.PubSub.subscribe(Ricqchet.PubSub, internal_topic(app_id, channel_name))

    if SubscriberTracker.track_join(app_id, channel_name) == :first_subscriber do
      enqueue_webhook("channel:occupied", app_id, channel_name)
    end

    if last_event_id do
      send(self(), {:recover_events, app_id, channel_name, last_event_id})
    else
      send(self(), {:maybe_send_cached_event, app_id, channel_name})
    end

    if channel_type(channel_name) == :presence do
      send(self(), :after_join_presence)
    end

    :telemetry.execute(
      [:ricqchet, :channels, :join],
      %{count: 1},
      %{application_id: app_id, channel_type: channel_type(channel_name)}
    )

    socket = assign(socket, :channel_name, channel_name)
    {:ok, socket}
  end

  # The customer auth endpoint is the authority on identity for private/presence
  # channels. When it returns a `user_id` (and optional `user_info`), trust those
  # over the client-supplied socket params so a holder of a (public) `subscribe`
  # key cannot impersonate another user in presence or client-event attribution.
  # When the endpoint returns no identity, the provisional client-supplied values
  # are kept (documented as unverified — see docs/channels.md).
  defp bind_identity(socket, auth_data) do
    socket
    |> maybe_bind(:user_id, auth_data["user_id"])
    |> maybe_bind(:user_info, auth_data["user_info"])
  end

  defp maybe_bind(socket, :user_id, user_id) when is_binary(user_id) and user_id != "" do
    assign(socket, :user_id, user_id)
  end

  defp maybe_bind(socket, :user_info, user_info) when is_map(user_info) do
    assign(socket, :user_info, user_info)
  end

  defp maybe_bind(socket, _key, _value), do: socket

  defp validate_client_channel("private-" <> _), do: :ok
  defp validate_client_channel("presence-" <> _), do: :ok
  defp validate_client_channel(_), do: {:error, "client_events_not_allowed"}

  # Rate limits client events per physical connection (`connection_id`), not per
  # client-supplied `user_id`, so a spoofed/rotated user_id cannot multiply a
  # single connection's event budget.
  defp check_client_rate(app_id, connection_id, channel_name) do
    limit =
      case NamespaceConfig.get_namespace_for_channel(app_id, channel_name) do
        {:ok, %{max_client_events_per_second: limit}} when is_integer(limit) -> limit
        _ -> 10
      end

    case ClientEventRateLimiter.check_rate(app_id, connection_id, limit) do
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

  # Internal, application-scoped PubSub topic. Server-published events and
  # presence are namespaced here so two applications using the same bare channel
  # name stay isolated, even though the client-facing socket topic is the bare name.
  defp internal_topic(app_id, channel_name), do: "channels:app:#{app_id}:#{channel_name}"

  defp enqueue_webhook(event, app_id, channel_name, opts \\ []) do
    %{application_id: app_id, channel_name: channel_name}
    |> maybe_put_opt(:user_id, opts)
    |> maybe_put_opt(:user_info, opts)
    |> then(&WebhookNotifier.enqueue(event, &1))
  end

  defp maybe_put_opt(map, key, opts) do
    case Keyword.get(opts, key) do
      nil -> map
      value -> Map.put(map, key, value)
    end
  end
end
