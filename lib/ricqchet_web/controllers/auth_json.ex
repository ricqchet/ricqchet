defmodule RicqchetWeb.AuthJSON do
  @moduledoc """
  JSON view for authentication responses.
  """

  alias Ricqchet.Users.User

  @doc """
  Renders authentication responses.

  Supported templates:
  - `registered.json` - registration success with user data
  - `email_verified.json` - email verification success with user data
  - `logged_in.json` - login success with user and tokens
  - `refreshed.json` - token refresh success
  - `message.json` - simple message response
  """
  def render("registered.json", %{user: user}) do
    %{
      user: user_json(user),
      message: "Registration successful. Please check your email to verify your account."
    }
  end

  def render("email_verified.json", %{user: user}) do
    %{
      user: user_json_with_confirmed(user),
      message: "Email verified successfully"
    }
  end

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

  defp user_json(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      role: user.role,
      status: user.status,
      tenant_id: user.tenant_id
    }
  end

  defp user_json_with_confirmed(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      status: user.status,
      confirmed_at: user.confirmed_at
    }
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
