defmodule RicqchetWeb.AuthJSON do
  @moduledoc """
  JSON view for authentication responses.
  """

  alias Ricqchet.Users.User

  @doc """
  Renders a successful registration response.
  """
  def render("registered.json", %{user: user}) do
    %{
      user: user_json(user),
      message: "Registration successful. Please check your email to verify your account."
    }
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
end
