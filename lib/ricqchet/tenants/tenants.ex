defmodule Ricqchet.Tenants do
  @moduledoc """
  Context module for tenant operations.
  """

  import Ecto.Query

  alias Ricqchet.Repo
  alias Ricqchet.Tenants.Tenant
  alias Ricqchet.Users.User

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

  # User management functions

  @doc """
  Counts the number of admin users in a tenant.
  """
  def count_admins(%Tenant{id: tenant_id}) do
    User
    |> where([u], u.tenant_id == ^tenant_id and u.role == "admin")
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Removes a user from a tenant by setting their status to suspended.

  This is a soft delete that preserves the user record but prevents access.
  """
  def remove_user_from_tenant(%User{} = user) do
    user
    |> Ecto.Changeset.change(%{status: "suspended"})
    |> Repo.update()
  end
end
