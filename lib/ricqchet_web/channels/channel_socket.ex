defmodule RicqchetWeb.Channels.ChannelSocket do
  @moduledoc """
  WebSocket endpoint for real-time channel subscriptions.

  Authenticates connections using API keys passed in socket params.
  This is separate from `UserSocket` (dashboard JWT auth) because channel
  clients are end-users of Ricqchet customers, not Ricqchet dashboard users.

  ## Connection

      wss://api.ricqchet.com/channels?api_key=<key>&user_id=<uid>&user_info=<json>

  ## Joining channels

  After connecting, clients join a channel using its **bare name** as the topic —
  there is no application prefix to construct:

      socket.channel("chat-room")
      socket.channel("private-orders")
      socket.channel("presence-lobby")
      socket.channel("orders.us.west")

  The application is resolved from the API key on the socket, so two applications
  can use the same channel name without colliding.

  ## Security

  API keys are passed via socket params during the WebSocket handshake.
  The key is verified using the existing prefix-based O(1) lookup with
  Argon2 constant-time verification. Connections are rejected if:

  - API key is missing, invalid, revoked, or expired
  - The associated application has `channels_enabled` set to false
  - The associated application or tenant is inactive
  """

  use Phoenix.Socket

  require Logger

  alias Ricqchet.ApiKeys
  alias Ricqchet.Channels.ConnectionTracker

  # Catch-all: clients join with the bare channel name as the topic (e.g.
  # "chat-room", "presence-lobby", "orders.us.west"). The application is derived
  # from the authenticated socket, not the topic, so `PubsubChannel.join/3` is the
  # sole validation gate. This must remain the last `channel` declaration — routes
  # match in declaration order and "*" matches every topic.
  channel "*", RicqchetWeb.Channels.PubsubChannel

  @impl Phoenix.Socket
  def connect(%{"api_key" => api_key} = params, socket, _connect_info) do
    with {:ok, application, tenant} <- authenticate(api_key),
         :ok <- check_connection_limit(application.id) do
      {:ok, setup_socket(socket, application, tenant, params)}
    else
      {:error, reason} ->
        Logger.debug("Channel socket auth failed: #{inspect(reason)}")
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    Logger.debug("Channel socket rejected: missing api_key param")
    :error
  end

  @impl Phoenix.Socket
  def id(socket) do
    "channel_socket:#{socket.assigns.application_id}:#{socket.assigns.user_id}"
  end

  defp check_connection_limit(application_id) do
    # `self()` is the socket transport process (connect/3 runs in the process that
    # becomes the long-lived socket); the tracker monitors it to release the slot
    # on disconnect, so the count stays per-socket rather than per-channel-join.
    case ConnectionTracker.track_connect(application_id, get_max_connections(), self()) do
      :ok -> :ok
      :limit_reached -> {:error, :connection_limit_reached}
    end
  end

  defp setup_socket(socket, application, tenant, params) do
    user_id = Map.get(params, "user_id", "anonymous")
    user_info = parse_user_info(Map.get(params, "user_info"))

    :telemetry.execute(
      [:ricqchet, :channels, :connection, :opened],
      %{count: 1},
      %{application_id: application.id}
    )

    socket
    |> assign(:application, application)
    |> assign(:application_id, application.id)
    |> assign(:tenant_id, tenant.id)
    |> assign(:user_id, user_id)
    |> assign(:user_info, user_info)
  end

  defp authenticate(api_key) do
    case ApiKeys.get_by_api_key(api_key) do
      %{application: application, tenant: tenant} ->
        if application.channels_enabled do
          {:ok, application, tenant}
        else
          {:error, :channels_not_enabled}
        end

      nil ->
        {:error, :invalid_api_key}
    end
  end

  defp parse_user_info(nil), do: %{}
  defp parse_user_info(""), do: %{}

  defp parse_user_info(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, info} when is_map(info) -> info
      _ -> %{}
    end
  end

  defp parse_user_info(_), do: %{}

  defp get_max_connections do
    case Application.get_env(:ricqchet, :channels) do
      nil -> nil
      config -> Keyword.get(config, :max_connections_per_app)
    end
  end
end
