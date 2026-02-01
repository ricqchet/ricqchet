defmodule Ricqchet.Users.User do
  @moduledoc """
  Schema for users.

  Users represent human accounts that can authenticate via email/password
  to manage tenants through the UI. Each user belongs to a tenant and has
  a role determining their permissions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          email: String.t() | nil,
          password_hash: String.t() | nil,
          status: String.t(),
          role: String.t(),
          confirmed_at: DateTime.t() | nil,
          last_login_at: DateTime.t() | nil,
          token_version: integer(),
          password: String.t() | nil,
          tenant_id: Ecto.UUID.t() | nil,
          tenant: Ricqchet.Tenants.Tenant.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "users" do
    field :email, :string
    field :password_hash, :string
    field :status, :string, default: "active"
    field :role, :string, default: "admin"
    field :confirmed_at, :utc_datetime_usec
    field :last_login_at, :utc_datetime_usec
    field :token_version, :integer, default: 1

    # Virtual field for the plaintext password (never persisted)
    field :password, :string, virtual: true

    belongs_to :tenant, Ricqchet.Tenants.Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :status, :role])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email address")
    |> validate_length(:email, max: 160)
    |> validate_inclusion(:status, ["active", "suspended", "pending"])
    |> validate_inclusion(:role, ["admin", "member", "viewer"])
    |> unique_constraint(:email)
    |> foreign_key_constraint(:tenant_id)
  end

  @doc """
  Changeset for user registration with password.
  """
  def registration_changeset(user, tenant, attrs) do
    user
    |> changeset(attrs)
    |> put_assoc(:tenant, tenant)
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> hash_password()
  end

  @doc """
  Changeset for changing password.
  """
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> hash_password()
  end

  @doc """
  Changeset for updating last_login_at timestamp.
  """
  def login_changeset(user) do
    change(user, %{last_login_at: DateTime.utc_now()})
  end

  @doc """
  Changeset for confirming a user's email.
  """
  def confirm_changeset(user) do
    change(user, %{confirmed_at: DateTime.utc_now(), status: "active"})
  end

  @doc """
  Changeset for incrementing the token version.

  This invalidates all existing JWT tokens for the user, effectively
  logging them out of all sessions.
  """
  def increment_token_version_changeset(user) do
    change(user, %{token_version: user.token_version + 1})
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        changeset
        |> put_change(:password_hash, Argon2.hash_pwd_salt(password))
        |> delete_change(:password)
    end
  end
end
