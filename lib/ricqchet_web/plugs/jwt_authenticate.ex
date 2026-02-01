defmodule RicqchetWeb.Plugs.JWTAuthenticate do
  @moduledoc """
  Plug for authenticating requests using JWT access tokens.

  Extracts the JWT from the Authorization header and validates it.
  If authentication succeeds, assigns are set for:
  - `current_user` - the authenticated user
  - `current_tenant` - the user's tenant
  - `current_scope` - a Scope struct containing user and tenant

  ## Usage

      plug RicqchetWeb.Plugs.JWTAuthenticate

  ## Token Validation

  The plug validates:
  1. Token signature (HS256)
  2. Token expiration
  3. Token type (must be "access")
  4. Token version matches user's current version
  5. User status is "active"
  """

  import Plug.Conn

  alias Ricqchet.Auth.Token
  alias Ricqchet.Repo
  alias Ricqchet.Scope
  alias Ricqchet.Users
  alias Ricqchet.Users.User

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with {:ok, token} <- extract_token(conn),
         {:ok, claims} <- Token.verify_access_token(token),
         {:ok, user} <- load_and_validate_user(claims) do
      scope = Scope.for_user(user)

      conn
      |> assign(:current_user, user)
      |> assign(:current_tenant, scope.tenant)
      |> assign(:current_scope, scope)
    else
      {:error, :token_expired} ->
        unauthorized(conn, "Token has expired")

      {:error, :invalid_token_version} ->
        unauthorized(conn, "Token has been invalidated")

      {:error, :user_not_active} ->
        unauthorized(conn, "User account is not active")

      _ ->
        unauthorized(conn, "Invalid or missing access token")
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, :missing_token}
    end
  end

  defp load_and_validate_user(%{"sub" => user_id, "ver" => token_version}) do
    case Users.get_user(user_id) do
      %User{token_version: ^token_version, status: status} = user
      when status in ["active", "pending"] ->
        {:ok, Repo.preload(user, :tenant)}

      %User{token_version: _different_version} ->
        {:error, :invalid_token_version}

      %User{status: _inactive_status} ->
        {:error, :user_not_active}

      nil ->
        {:error, :user_not_found}
    end
  end

  defp unauthorized(conn, message) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.put_view(json: RicqchetWeb.ErrorJSON)
    |> Phoenix.Controller.render(:error,
      error: "unauthorized",
      message: message
    )
    |> halt()
  end
end
