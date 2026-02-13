defmodule RicqchetWeb.ChannelController do
  @moduledoc """
  Controller for channel operations.

  Provides endpoints for publishing events to channels and querying
  active channel information.
  """

  use RicqchetWeb, :controller

  alias Ricqchet.Channels

  action_fallback RicqchetWeb.FallbackController

  @max_channels 10

  @doc """
  Publishes an event to one or more channels.

  ## Single channel

      POST /v1/channels/events
      {"channel": "chat-room1", "event": "new-message", "data": {"text": "Hello!"}}

  ## Multiple channels

      POST /v1/channels/events
      {"channels": ["chat-room1", "chat-room2"], "event": "announcement", "data": {"text": "Hi"}}
  """
  def create(conn, params) do
    application = conn.assigns.current_application

    with :ok <- check_channels_enabled(application),
         {:ok, channels} <- extract_channels(params),
         {:ok, event} <- extract_event(params),
         :ok <- validate_all_channels(channels),
         {:ok, event_ids} <- publish_to_channels(application.id, channels, event, params) do
      conn
      |> put_status(:accepted)
      |> render(:created, event_ids: event_ids, channels: channels)
    end
  end

  @doc """
  Lists active channels for the current application.

      GET /v1/channels
  """
  def index(conn, _params) do
    application = conn.assigns.current_application

    with :ok <- check_channels_enabled(application) do
      channels = Channels.list_channels(application.id)
      render(conn, :index, channels: channels)
    end
  end

  @doc """
  Gets info for a specific channel.

      GET /v1/channels/:channel_name
  """
  def show(conn, %{"channel_name" => channel_name}) do
    application = conn.assigns.current_application

    with :ok <- check_channels_enabled(application) do
      info = Channels.get_channel_info(application.id, channel_name)
      render(conn, :show, channel: info)
    end
  end

  defp publish_to_channels(application_id, channels, event, params) do
    data = Map.get(params, "data", %{})
    socket_id = Map.get(params, "socket_id")
    opts = if socket_id, do: [socket_id: socket_id], else: []

    event_ids =
      Enum.map(channels, fn channel ->
        {:ok, result} = Channels.publish_event(application_id, channel, event, data, opts)
        result.id
      end)

    {:ok, event_ids}
  end

  defp check_channels_enabled(application) do
    if application.channels_enabled do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp extract_channels(%{"channel" => channel}) when is_binary(channel) and channel != "" do
    {:ok, [channel]}
  end

  defp extract_channels(%{"channels" => channels}) when is_list(channels) do
    channels = Enum.filter(channels, &(is_binary(&1) and &1 != ""))

    cond do
      channels == [] ->
        {:error, :validation, "channels list cannot be empty"}

      length(channels) > @max_channels ->
        {:error, :validation, "cannot publish to more than #{@max_channels} channels at once"}

      true ->
        {:ok, channels}
    end
  end

  defp extract_channels(_) do
    {:error, :validation, "channel or channels is required"}
  end

  defp extract_event(%{"event" => event}) when is_binary(event) and event != "" do
    {:ok, event}
  end

  defp extract_event(_) do
    {:error, :validation, "event is required"}
  end

  defp validate_all_channels(channels) do
    Enum.reduce_while(channels, :ok, fn channel, :ok ->
      case Channels.validate_channel_name(channel) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, :validation, reason}}
      end
    end)
  end
end
