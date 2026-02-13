defmodule RicqchetWeb.Channels.ChannelSocket do
  @moduledoc """
  WebSocket endpoint for real-time channel subscriptions.

  Authenticates connections using API keys passed in socket params.
  This is separate from `UserSocket` (dashboard JWT auth) because channel
  clients are end-users of Ricqchet customers, not Ricqchet dashboard users.

  ## Connection

      wss://api.ricqchet.com/channels?api_key=<key>&user_id=<uid>&user_info=<json>

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

  channel "channels:*", RicqchetWeb.Channels.PubsubChannel

  @impl Phoenix.Socket
  def connect(%{"api_key" => api_key} = params, socket, _connect_info) do
    case authenticate(api_key) do
      {:ok, application, tenant} ->
        user_id = Map.get(params, "user_id", "anonymous")
        user_info = parse_user_info(Map.get(params, "user_info"))

        socket =
          socket
          |> assign(:application, application)
          |> assign(:application_id, application.id)
          |> assign(:tenant_id, tenant.id)
          |> assign(:user_id, user_id)
          |> assign(:user_info, user_info)

        {:ok, socket}

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
end
