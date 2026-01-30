defmodule Relay.Tenants do
  @moduledoc """
  Context module for tenant operations.
  """

  import Ecto.Query

  alias Relay.Repo
  alias Relay.Tenants.Tenant

  @doc """
  Creates a new tenant with an auto-generated API key.

  Returns `{:ok, %Tenant{api_key: "..."}}` with the plaintext API key
  available in the `api_key` virtual field. This is the only time the
  plaintext key is available - it is not stored in the database.

  ## Examples

      iex> create_tenant(%{name: "My App"})
      {:ok, %Tenant{api_key: "generated_key_here"}}

  """
  def create_tenant(attrs \\ %{}) do
    %Tenant{}
    |> Tenant.create_changeset(attrs)
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
  Gets a tenant by API key.

  This performs an Argon2 verification against all tenants' hashed keys.
  Returns `nil` if no matching tenant is found.

  ## Examples

      iex> get_by_api_key("valid_key")
      %Tenant{}

      iex> get_by_api_key("invalid_key")
      nil

  """
  def get_by_api_key(api_key) when is_binary(api_key) do
    # Get all active tenants and verify against each hash
    # This is O(n) but acceptable for reasonable tenant counts
    # For high scale, consider using a prefix-based lookup
    Tenant
    |> where([t], t.status == "active")
    |> Repo.all()
    |> Enum.find(fn tenant ->
      Argon2.verify_pass(api_key, tenant.api_key_hash)
    end)
  end

  def get_by_api_key(_), do: nil

  @doc """
  Updates a tenant.
  """
  def update_tenant(%Tenant{} = tenant, attrs) do
    tenant
    |> Tenant.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists all tenants.
  """
  def list_tenants do
    Repo.all(Tenant)
  end
end
