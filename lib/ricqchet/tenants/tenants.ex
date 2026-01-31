defmodule Ricqchet.Tenants do
  @moduledoc """
  Context module for tenant operations.
  """

  import Ecto.Query

  alias Ricqchet.Repo
  alias Ricqchet.Tenants.Tenant

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

  Uses a prefix-based O(1) lookup to find the candidate tenant,
  then performs constant-time Argon2 verification.

  Returns `nil` if no matching tenant is found.

  ## Examples

      iex> get_by_api_key("valid_key")
      %Tenant{}

      iex> get_by_api_key("invalid_key")
      nil

  """
  def get_by_api_key(api_key) when is_binary(api_key) do
    prefix_length = Tenant.api_key_prefix_length()
    prefix = String.slice(api_key, 0, prefix_length)

    # O(1) lookup using the prefix index
    tenant =
      Tenant
      |> where([t], t.api_key_prefix == ^prefix)
      |> where([t], t.status == "active")
      |> Repo.one()

    # Constant-time verification to prevent timing attacks
    verify_api_key(tenant, api_key)
  end

  def get_by_api_key(_), do: nil

  # Always perform the hash comparison to ensure constant timing
  defp verify_api_key(nil, _api_key) do
    # Perform a dummy verification to prevent timing attacks
    Argon2.no_user_verify()
    nil
  end

  defp verify_api_key(tenant, api_key) do
    if Argon2.verify_pass(api_key, tenant.api_key_hash) do
      tenant
    else
      nil
    end
  end

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
