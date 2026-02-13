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
  alias Ricqchet.Channels.SubscriberTracker
  alias RicqchetWeb.Channels.ChannelSocket

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
      push(socket, payload.event, %{data: payload.data, channel: payload.channel})
      {:noreply, socket}
    end
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

  defp authorize_and_join(app_id, channel_name, _params, socket) do
    with :ok <- verify_app_ownership(app_id, socket),
         :ok <- validate_name(channel_name) do
      case channel_type(channel_name) do
        :public -> do_join(app_id, channel_name, socket)
        _authenticated -> join_with_auth(app_id, channel_name, socket)
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

  defp join_with_auth(app_id, channel_name, socket) do
    application = socket.assigns.application
    user_id = socket.assigns.user_id
    socket_id = ChannelSocket.id(socket)

    case Auth.authorize(application, channel_name, user_id, socket_id) do
      {:ok, _auth_data} ->
        do_join(app_id, channel_name, socket)

      {:error, :forbidden} ->
        {:error, %{reason: "forbidden"}}

      {:error, :no_auth_endpoint} ->
        {:error, %{reason: "auth_endpoint_not_configured"}}

      {:error, :auth_unavailable} ->
        {:error, %{reason: "auth_unavailable"}}
    end
  end

  defp do_join(app_id, channel_name, socket) do
    topic = "channels:app:#{app_id}:#{channel_name}"
    Phoenix.PubSub.subscribe(Ricqchet.PubSub, topic)
    SubscriberTracker.track_join(app_id, channel_name)
    {:ok, socket}
  end

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
