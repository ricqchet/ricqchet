defmodule Ricqchet.Auth.RefreshToken do
  @moduledoc """
  Schema for refresh tokens.

  Refresh tokens are long-lived tokens (7 days) used to obtain new access tokens
  without requiring the user to re-authenticate. The token itself is hashed before
  storage; only the hash is persisted.

  ## Token Lifecycle

  1. Created on login with a random token value
  2. Token value returned to client (only time plaintext is available)
  3. Client uses token to request new access tokens
  4. Token is revoked on logout or can expire naturally
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ricqchet.Users.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "refresh_tokens" do
    field :token_hash, :string
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    # Virtual field for the plaintext token (only available on creation)
    field :token, :string, virtual: true

    belongs_to :user, User

    timestamps(type: :utc_datetime_usec)
  end

  @token_bytes 32

  @doc """
  Changeset for creating a new refresh token.

  Generates a secure random token and hashes it before storage.
  """
  def create_changeset(refresh_token, user, attrs \\ %{}) do
    ttl = Application.get_env(:ricqchet, :jwt_refresh_token_ttl, 7 * 24 * 60 * 60)
    token = generate_token()
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :second)

    refresh_token
    |> cast(attrs, [])
    |> put_change(:token, token)
    |> put_change(:token_hash, hash_token(token))
    |> put_change(:expires_at, expires_at)
    |> put_assoc(:user, user)
    |> validate_required([:token_hash, :expires_at])
  end

  @doc """
  Changeset for revoking a refresh token.
  """
  def revoke_changeset(refresh_token) do
    change(refresh_token, %{revoked_at: DateTime.utc_now()})
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
  Checks if a refresh token is valid (not expired and not revoked).
  """
  def valid?(%__MODULE__{} = token) do
    not revoked?(token) and not expired?(token)
  end

  @doc """
  Checks if a refresh token has been revoked.
  """
  def revoked?(%__MODULE__{revoked_at: nil}), do: false
  def revoked?(%__MODULE__{revoked_at: _}), do: true

  @doc """
  Checks if a refresh token has expired.
  """
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
