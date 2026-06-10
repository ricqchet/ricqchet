defmodule RicqchetWeb.TenantJSON do
  @moduledoc """
  JSON views for tenant endpoints.
  """

  alias Ricqchet.Tenants.Tenant

  @doc """
  Renders tenant JSON responses.

  - `show.json` - Tenant details (admins see signing_secret)
  - `signing_secret.json` - Base64-encoded signing secret
  """
  def render(template, assigns)

  def render("show.json", %{tenant: tenant, is_admin: is_admin}) do
    tenant_json(tenant, is_admin)
  end

  def render("signing_secret.json", %{signing_secret: signing_secret}) do
    %{
      signing_secret: Base.encode64(signing_secret)
    }
  end

  defp tenant_json(%Tenant{} = tenant, true = _is_admin) do
    %{
      id: tenant.id,
      name: tenant.name,
      status: tenant.status,
      default_max_retries: tenant.default_max_retries,
      signing_secret: Base.encode64(tenant.signing_secret),
      inserted_at: tenant.inserted_at,
      updated_at: tenant.updated_at
    }
  end

  defp tenant_json(%Tenant{} = tenant, false = _is_admin) do
    %{
      id: tenant.id,
      name: tenant.name,
      status: tenant.status,
      default_max_retries: tenant.default_max_retries,
      inserted_at: tenant.inserted_at,
      updated_at: tenant.updated_at
    }
  end
end
