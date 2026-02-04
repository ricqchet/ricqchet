defmodule RicqchetWeb.UserSocket do
  @moduledoc """
  WebSocket entry point for real-time dashboard activity.

  Authenticates connections using JWT tokens passed in socket params.

  ## Security Considerations

  JWT tokens are passed via socket params (URL query string) during the WebSocket
  handshake. This is a common pattern for WebSocket authentication since the
  WebSocket API does not support custom headers during connection.

  To mitigate token exposure risks:
  - Use short-lived access tokens (configured in `Ricqchet.Auth.Token`)
  - Ensure reverse proxies/load balancers do not log query parameters
  - Tokens are validated for user status and token version on each connection

  For enhanced security in production, consider implementing ticket-based auth
  where a short-lived, single-use ticket is exchanged for the WebSocket connection.
  """

  use Phoenix.Socket

  require Logger

  alias Ricqchet.Auth.Token
  alias Ricqchet.Users

  channel "activity:*", RicqchetWeb.ActivityChannel

  @impl Phoenix.Socket
  def connect(%{"token" => token}, socket, _connect_info) do
    case authenticate(token) do
      {:ok, user, tenant} ->
        socket =
          socket
          |> assign(:user_id, user.id)
          |> assign(:tenant_id, tenant.id)

        {:ok, socket}

      {:error, reason} ->
        Logger.debug("WebSocket authentication failed: #{inspect(reason)}")
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    Logger.debug("WebSocket connection rejected: missing token")
    :error
  end

  @impl Phoenix.Socket
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"

  # Authentication logic

  defp authenticate(token) do
    with {:ok, claims} <- Token.verify_access_token(token),
         {:ok, user} <- load_and_validate_user(claims) do
      {:ok, user, user.tenant}
    end
  end

  defp load_and_validate_user(%{"sub" => user_id, "ver" => token_version}) do
    case Users.get_user(user_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        validate_user(user, token_version)
    end
  end

  defp load_and_validate_user(_claims), do: {:error, :invalid_claims}

  defp validate_user(user, token_version) do
    cond do
      user.status not in ["active", "pending"] ->
        {:error, :user_inactive}

      user.token_version != token_version ->
        {:error, :token_revoked}

      true ->
        user = Ricqchet.Repo.preload(user, :tenant)
        {:ok, user}
    end
  end
end
