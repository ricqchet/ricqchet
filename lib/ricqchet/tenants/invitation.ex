defmodule Ricqchet.Tenants.Invitation do
  @moduledoc """
  Schema for tenant invitations.

  Invitations allow admins to invite new users to join their tenant.
  Each invitation has a token that is sent via email and expires after 7 days.

  ## Invitation Lifecycle

  1. Admin creates invitation with email and role
  2. Token sent to user's email in an invitation link
  3. User clicks link, provides password, accepts invitation
  4. User is created (if new) or added to tenant (if existing)
  5. Invitation marked as accepted
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ricqchet.Tenants.Tenant
  alias Ricqchet.Users.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # 7 days in seconds
  @default_ttl 7 * 24 * 60 * 60
  @token_bytes 32

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          email: String.t() | nil,
          role: String.t(),
          status: String.t(),
          token_hash: String.t() | nil,
          token: String.t() | nil,
          expires_at: DateTime.t() | nil,
          accepted_at: DateTime.t() | nil,
          tenant_id: Ecto.UUID.t() | nil,
          tenant: Tenant.t() | Ecto.Association.NotLoaded.t() | nil,
          invited_by_id: Ecto.UUID.t() | nil,
          invited_by: User.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "invitations" do
    field :email, :string
    field :role, :string, default: "member"
    field :status, :string, default: "pending"
    field :token_hash, :string
    field :expires_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec

    # Virtual field for the plaintext token (only available on creation)
    field :token, :string, virtual: true

    belongs_to :tenant, Tenant
    belongs_to :invited_by, User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new invitation.

  Generates a secure random token and hashes it before storage.
  """
  def create_changeset(invitation, tenant, invited_by, attrs) do
    ttl = Map.get(attrs, :ttl, @default_ttl)
    token = generate_token()
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :second)

    invitation
    |> cast(attrs, [:email, :role])
    |> validate_required([:email, :role])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email address")
    |> validate_length(:email, max: 160)
    |> validate_inclusion(:role, ["admin", "member", "viewer"])
    |> put_change(:token, token)
    |> put_change(:token_hash, hash_token(token))
    |> put_change(:expires_at, expires_at)
    |> put_change(:status, "pending")
    |> put_assoc(:tenant, tenant)
    |> put_assoc(:invited_by, invited_by)
    |> unique_constraint([:email, :tenant_id],
      name: :invitations_email_tenant_id_index,
      message: "already has a pending invitation"
    )
  end

  @doc """
  Changeset for accepting an invitation.
  """
  def accept_changeset(invitation) do
    change(invitation, %{
      status: "accepted",
      accepted_at: DateTime.utc_now()
    })
  end

  @doc """
  Changeset for revoking an invitation.
  """
  def revoke_changeset(invitation) do
    change(invitation, %{status: "revoked"})
  end

  @doc """
  Generates a secure random token.
  """
  def generate_token do
    @token_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Hashes a token for storage.
  """
  def hash_token(token) when is_binary(token) do
    :sha256
    |> :crypto.hash(token)
    |> Base.encode64()
  end

  @doc """
  Checks if an invitation is valid (pending and not expired).
  """
  def valid?(%__MODULE__{status: "pending"} = invitation) do
    not expired?(invitation)
  end

  def valid?(_invitation), do: false

  @doc """
  Checks if an invitation has expired.
  """
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
