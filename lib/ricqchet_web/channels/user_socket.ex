defmodule RicqchetWeb.UserSocket do
  @moduledoc """
  WebSocket entry point for real-time dashboard activity.

  Authenticates connections using JWT tokens passed in socket params.
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

  defp load_and_validate_user(%{"sub" => user_id, "token_version" => token_version}) do
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
