defmodule RicqchetWeb.AuthJSON do
  @moduledoc """
  JSON view for authentication responses.
  """

  alias Ricqchet.Users.User

  @doc """
  Renders authentication responses.

  Supported templates:
  - `logged_in.json` - login success with user and tokens
  - `refreshed.json` - token refresh success
  - `message.json` - simple message response
  """
  def render("logged_in.json", %{
        user: user,
        access_token: access_token,
        refresh_token: refresh_token,
        expires_in: expires_in
      }) do
    %{
      user: user_json_with_tenant(user),
      access_token: access_token,
      refresh_token: refresh_token,
      expires_in: expires_in
    }
  end

  def render("refreshed.json", %{access_token: access_token, expires_in: expires_in}) do
    %{
      access_token: access_token,
      expires_in: expires_in
    }
  end

  def render("message.json", %{message: message}) do
    %{message: message}
  end

  defp user_json_with_tenant(%User{} = user) do
    tenant = user.tenant

    %{
      id: user.id,
      email: user.email,
      role: user.role,
      status: user.status,
      tenant_id: user.tenant_id,
      tenant_name: tenant && tenant.name
    }
  end
end
