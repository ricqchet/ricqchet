defmodule Ricqchet.Auth.EmailVerificationToken do
  @moduledoc """
  Schema for email verification tokens.

  Email verification tokens are used to confirm a user's email address after
  registration. The token itself is hashed before storage; only the hash is persisted.

  ## Token Lifecycle

  1. Created on registration with a random token value
  2. Token sent to user's email in a verification link
  3. User clicks link, token is verified and user is marked as confirmed
  4. Token expires after 24 hours if unused
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ricqchet.Users.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # 24 hours in seconds
  @default_ttl 24 * 60 * 60
  @token_bytes 32

  schema "email_verification_tokens" do
    field :token_hash, :string
    field :expires_at, :utc_datetime_usec

    # Virtual field for the plaintext token (only available on creation)
    field :token, :string, virtual: true

    belongs_to :user, User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new email verification token.

  Generates a secure random token and hashes it before storage.
  """
  def create_changeset(verification_token, user, attrs \\ %{}) do
    ttl = Map.get(attrs, :ttl, @default_ttl)
    token = generate_token()
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :second)

    verification_token
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
  Checks if a verification token is valid (not expired).
  """
  def valid?(%__MODULE__{} = token) do
    not expired?(token)
  end

  @doc """
  Checks if a verification token has expired.
  """
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
