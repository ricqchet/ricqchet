defmodule Ricqchet.Tenants do
  @moduledoc """
  Context module for tenant operations.
  """

  alias Ricqchet.Repo
  alias Ricqchet.Tenants.Tenant

  @doc """
  Creates a new tenant.

  ## Examples

      iex> create_tenant(%{name: "My Organization"})
      {:ok, %Tenant{}}

  """
  def create_tenant(attrs \\ %{}) do
    %Tenant{}
    |> Tenant.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a tenant by ID.
  """
  def get_tenant(id), do: Repo.get(Tenant, id)

  @doc """
  Gets a tenant by ID, raising if not found.
  """
  def get_tenant!(id), do: Repo.get!(Tenant, id)

  @doc """
  Updates a tenant.
  """
  def update_tenant(%Tenant{} = tenant, attrs) do
    tenant
    |> Tenant.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a tenant.
  """
  def delete_tenant(%Tenant{} = tenant) do
    Repo.delete(tenant)
  end

  @doc """
  Lists all tenants.
  """
  def list_tenants do
    Repo.all(Tenant)
  end
end
