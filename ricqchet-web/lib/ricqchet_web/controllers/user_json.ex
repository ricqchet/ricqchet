defmodule RicqchetWeb.UserJSON do
  @moduledoc """
  JSON view for user responses.
  """

  alias Ricqchet.Tenants.Tenant
  alias Ricqchet.Users.User

  @doc """
  Renders a user profile.
  """
  def render("show.json", %{user: user, tenant: tenant}) do
    user_json(user, tenant)
  end

  defp user_json(%User{} = user, %Tenant{} = tenant) do
    %{
      id: user.id,
      email: user.email,
      role: user.role,
      status: user.status,
      tenant_id: user.tenant_id,
      tenant_name: tenant.name,
      confirmed_at: user.confirmed_at,
      last_login_at: user.last_login_at,
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end
end
