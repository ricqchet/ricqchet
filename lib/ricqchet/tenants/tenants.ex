defmodule Ricqchet.Tenants do
  @moduledoc """
  Context module for tenant operations.
  """

  import Ecto.Query

  alias Ricqchet.Repo
  alias Ricqchet.Tenants.Invitation
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

  # Invitation functions

  @doc """
  Creates an invitation to join a tenant.

  The invitation includes a token that can be used to accept the invitation.
  The token is returned in the virtual field and should be sent to the invitee.

  ## Parameters

  - tenant: The tenant to invite the user to
  - params: Map containing email, role, and optionally invited_by_id

  ## Examples

      iex> invite_user(tenant, %{"email" => "new@example.com", "role" => "member"})
      {:ok, %Invitation{token: "..."}}

  """
  def invite_user(%Tenant{} = tenant, %User{} = invited_by, params) do
    %Invitation{}
    |> Invitation.create_changeset(tenant, invited_by, params)
    |> Repo.insert()
  end

  def invite_user(%Tenant{} = tenant, params) do
    # When no invited_by user is provided (e.g., system-generated invitations)
    %Invitation{}
    |> Invitation.create_changeset(tenant, nil, params)
    |> Repo.insert()
  end

  @doc """
  Gets an invitation by its token.
  """
  def get_invitation_by_token(token) when is_binary(token) do
    token_hash = Invitation.hash_token(token)

    Invitation
    |> where([i], i.token_hash == ^token_hash)
    |> Repo.one()
  end

  @doc """
  Gets an invitation by ID.
  """
  def get_invitation(id), do: Repo.get(Invitation, id)

  @doc """
  Marks an invitation as accepted.
  """
  def accept_invitation(%Invitation{} = invitation) do
    invitation
    |> Invitation.accept_changeset()
    |> Repo.update()
  end

  @doc """
  Revokes an invitation.
  """
  def revoke_invitation(%Invitation{} = invitation) do
    invitation
    |> Invitation.revoke_changeset()
    |> Repo.update()
  end

  @doc """
  Lists pending invitations for a tenant.
  """
  def list_pending_invitations(%Tenant{id: tenant_id}) do
    Invitation
    |> where([i], i.tenant_id == ^tenant_id and i.status == "pending")
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
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
