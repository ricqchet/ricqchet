defmodule Ricqchet.Auth.PasswordResetToken do
  @moduledoc """
  Schema for password reset tokens.

  Password reset tokens are used to allow users to reset their password when
  they've forgotten it. The token itself is hashed before storage; only the
  hash is persisted.

  ## Token Lifecycle

  1. Created when user requests password reset via forgot-password endpoint
  2. Token sent to user's email in a password reset link
  3. User clicks link, submits new password with token
  4. Token is validated, password updated, token deleted
  5. Token expires after 1 hour if unused
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ricqchet.Users.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # 1 hour in seconds
  @default_ttl 60 * 60
  @token_bytes 32

  schema "password_reset_tokens" do
    field :token_hash, :string
    field :expires_at, :utc_datetime_usec

    # Virtual field for the plaintext token (only available on creation)
    field :token, :string, virtual: true

    belongs_to :user, User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new password reset token.

  Generates a secure random token and hashes it before storage.
  """
  def create_changeset(reset_token, user, attrs \\ %{}) do
    ttl = Map.get(attrs, :ttl, @default_ttl)
    token = generate_token()
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :second)

    reset_token
    |> cast(attrs, [])
    |> put_change(:token, token)
    |> put_change(:token_hash, hash_token(token))
    |> put_change(:expires_at, expires_at)
    |> put_assoc(:user, user)
    |> validate_required([:token_hash, :expires_at])
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
  Checks if a reset token is valid (not expired).
  """
  def valid?(%__MODULE__{} = token) do
    not expired?(token)
  end

  @doc """
  Checks if a reset token has expired.
  """
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
