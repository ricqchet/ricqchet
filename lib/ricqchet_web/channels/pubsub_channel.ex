defmodule RicqchetWeb.Channels.PubsubChannel do
  @moduledoc """
  Phoenix Channel for real-time channel subscriptions.

  Handles join/leave for public channels with tenant isolation.
  Events published via the REST API are broadcast through PubSub
  and pushed to connected clients.

  ## Topic format

      channels:app:<application_id>:<channel_name>

  ## Channel types (by name prefix)

  - No prefix: public channel (Phase 1)
  - `private-`: private channel (Phase 2)
  - `presence-`: presence channel (Phase 3)
  """

  use RicqchetWeb, :channel

  require Logger

  alias Ricqchet.Channels.SubscriberTracker

  @channel_name_regex ~r/\A[a-zA-Z0-9_-]{1,164}\z/

  @impl Phoenix.Channel
  def join("channels:app:" <> rest, _params, socket) do
    case parse_topic(rest) do
      {:ok, app_id, channel_name} ->
        cond do
          app_id != socket.assigns.application_id ->
            {:error, %{reason: "unauthorized"}}

          not valid_channel_name?(channel_name) ->
            {:error, %{reason: "invalid_channel_name"}}

          private_or_presence?(channel_name) ->
            {:error, %{reason: "channel_type_not_supported"}}

          true ->
            topic = "channels:app:#{app_id}:#{channel_name}"
            Phoenix.PubSub.subscribe(Ricqchet.PubSub, topic)
            SubscriberTracker.track_join(app_id, channel_name)
            {:ok, socket}
        end

      :error ->
        {:error, %{reason: "invalid_topic"}}
    end
  end

  def join(_topic, _params, _socket) do
    {:error, %{reason: "invalid_topic"}}
  end

  @impl Phoenix.Channel
  def handle_info({:channel_event, payload}, socket) do
    # Skip sending to the socket that originated the event
    if payload[:socket_id] && payload[:socket_id] == socket_id(socket) do
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

  defp valid_channel_name?(name), do: Regex.match?(@channel_name_regex, name)

  defp private_or_presence?(name) do
    String.starts_with?(name, "private-") or String.starts_with?(name, "presence-")
  end

  defp socket_id(socket) do
    "channel_socket:#{socket.assigns.application_id}:#{socket.assigns.user_id}"
  end
end
