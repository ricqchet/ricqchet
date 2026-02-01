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
end
