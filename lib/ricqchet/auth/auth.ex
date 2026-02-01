defmodule Ricqchet.Auth do
  @moduledoc """
  Context module for authentication operations.

  Provides functions for user registration, login, logout, token management,
  and email verification.
  """

  import Ecto.Query

  alias Ricqchet.Auth.EmailVerificationToken
  alias Ricqchet.Auth.RefreshToken
  alias Ricqchet.Auth.Token
  alias Ricqchet.Repo
  alias Ricqchet.Tenants
  alias Ricqchet.Users
  alias Ricqchet.Users.User

  @doc """
  Registers a new user and creates their tenant.

  Creates a tenant and user atomically, then generates an email verification token.
  Returns the user and verification token (for sending the verification email).

  ## Options

  - `:tenant_name` - Name for the new tenant (required)
  - `:email` - User's email address (required)
  - `:password` - User's password (required)

  ## Examples

      iex> register_user(%{tenant_name: "Acme", email: "user@example.com", password: "secret123456"})
      {:ok, %{user: %User{}, verification_token: "abc..."}}

      iex> register_user(%{email: "invalid"})
      {:error, :user, %Ecto.Changeset{}, %{}}
  """
  def register_user(attrs) do
    tenant_attrs = %{name: attrs[:tenant_name] || attrs["tenant_name"]}

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:tenant, fn _repo, _changes ->
        Tenants.create_tenant(tenant_attrs)
      end)
      |> Ecto.Multi.run(:user, fn _repo, %{tenant: tenant} ->
        user_attrs = Map.merge(attrs, %{"status" => "pending", "role" => "admin"})
        Users.create_user(tenant, user_attrs)
      end)
      |> Ecto.Multi.run(:verification_token, fn _repo, %{user: user} ->
        create_email_verification_token(user)
      end)

    case Repo.transaction(multi) do
      {:ok, %{user: user, verification_token: token}} ->
        {:ok, %{user: user, verification_token: token.token}}

      {:error, step, changeset, _changes} ->
        {:error, step, changeset}
    end
  end

  @doc """
  Authenticates a user and generates tokens.

  Verifies the user's credentials and email verification status,
  then generates access and refresh tokens.

  Returns `{:error, :email_not_verified}` if the user hasn't confirmed their email.

  ## Examples

      iex> login("user@example.com", "password123456")
      {:ok, %{user: %User{}, access_token: "...", refresh_token: "...", expires_in: 900}}

      iex> login("user@example.com", "wrong")
      {:error, :invalid_credentials}
  """
  def login(email, password) do
    with {:ok, user} <- Users.authenticate_user(email, password),
         :ok <- verify_email_confirmed(user),
         {:ok, user} <- Users.touch_last_login(user),
         {:ok, access_token, _claims} <- Token.generate_access_token(user),
         {:ok, refresh_token} <- create_refresh_token(user) do
      {:ok,
       %{
         user: Repo.preload(user, :tenant),
         access_token: access_token,
         refresh_token: refresh_token.token,
         expires_in: Application.get_env(:ricqchet, :jwt_access_token_ttl, 900)
       }}
    end
  end

  @doc """
  Logs out a user by revoking their refresh token.

  ## Options

  - `:everywhere` - If true, increments the user's token version to invalidate
    all sessions. Default: false.

  ## Examples

      iex> logout(refresh_token)
      :ok

      iex> logout(refresh_token, everywhere: true)
      :ok
  """
  def logout(refresh_token_string, opts \\ []) do
    everywhere = Keyword.get(opts, :everywhere, false)

    with {:ok, refresh_token} <- get_refresh_token_by_token(refresh_token_string),
         {:ok, _} <- revoke_refresh_token(refresh_token) do
      if everywhere do
        user = Repo.preload(refresh_token, :user).user
        Users.increment_token_version(user)
      end

      :ok
    else
      {:error, :not_found} -> :ok
      error -> error
    end
  end

  @doc """
  Refreshes an access token using a refresh token.

  Validates the refresh token and generates a new access token.
  The refresh token must be valid (not expired, not revoked) and
  the user's token version must match.

  ## Examples

      iex> refresh_access_token("refresh-token-string")
      {:ok, %{access_token: "...", expires_in: 900}}

      iex> refresh_access_token("invalid")
      {:error, :invalid_refresh_token}
  """
  def refresh_access_token(refresh_token_string) do
    with {:ok, refresh_token} <- get_refresh_token_by_token(refresh_token_string),
         true <- RefreshToken.valid?(refresh_token),
         refresh_token <- Repo.preload(refresh_token, :user),
         {:ok, access_token, _claims} <- Token.generate_access_token(refresh_token.user) do
      {:ok,
       %{
         access_token: access_token,
         expires_in: Application.get_env(:ricqchet, :jwt_access_token_ttl, 900)
       }}
    else
      false -> {:error, :invalid_refresh_token}
      {:error, :not_found} -> {:error, :invalid_refresh_token}
    end
  end

  @doc """
  Verifies an email verification token and confirms the user.

  ## Examples

      iex> verify_email("verification-token")
      {:ok, %User{confirmed_at: ~U[...]}}

      iex> verify_email("invalid")
      {:error, :invalid_token}
  """
  def verify_email(token_string) do
    with {:ok, verification_token} <- get_email_verification_token_by_token(token_string),
         true <- EmailVerificationToken.valid?(verification_token),
         verification_token <- Repo.preload(verification_token, :user),
         {:ok, user} <- Users.confirm_user(verification_token.user),
         {:ok, _} <- delete_email_verification_tokens_for_user(user) do
      {:ok, user}
    else
      false -> {:error, :token_expired}
      {:error, :not_found} -> {:error, :invalid_token}
      error -> error
    end
  end

  @doc """
  Creates a new email verification token for a user.

  Deletes any existing verification tokens for the user first.

  ## Examples

      iex> create_email_verification_token(user)
      {:ok, %EmailVerificationToken{token: "abc..."}}
  """
  def create_email_verification_token(%User{} = user) do
    # Delete existing tokens first
    delete_email_verification_tokens_for_user(user)

    %EmailVerificationToken{}
    |> EmailVerificationToken.create_changeset(user)
    |> Repo.insert()
  end

  @doc """
  Creates a refresh token for a user.
  """
  def create_refresh_token(%User{} = user) do
    %RefreshToken{}
    |> RefreshToken.create_changeset(user)
    |> Repo.insert()
  end

  @doc """
  Revokes a refresh token.
  """
  def revoke_refresh_token(%RefreshToken{} = token) do
    token
    |> RefreshToken.revoke_changeset()
    |> Repo.update()
  end

  @doc """
  Revokes all refresh tokens for a user.
  """
  def revoke_all_refresh_tokens_for_user(%User{id: user_id}) do
    now = DateTime.utc_now()

    RefreshToken
    |> where([t], t.user_id == ^user_id and is_nil(t.revoked_at))
    |> Repo.update_all(set: [revoked_at: now])

    :ok
  end

  # Private functions

  defp verify_email_confirmed(%User{confirmed_at: nil}), do: {:error, :email_not_verified}
  defp verify_email_confirmed(%User{}), do: :ok

  defp get_refresh_token_by_token(token_string) when is_binary(token_string) do
    token_hash = RefreshToken.hash_token(token_string)

    result =
      RefreshToken
      |> where([t], t.token_hash == ^token_hash)
      |> Repo.one()

    case result do
      nil -> {:error, :not_found}
      token -> {:ok, token}
    end
  end

  defp get_email_verification_token_by_token(token_string) when is_binary(token_string) do
    token_hash = EmailVerificationToken.hash_token(token_string)

    result =
      EmailVerificationToken
      |> where([t], t.token_hash == ^token_hash)
      |> Repo.one()

    case result do
      nil -> {:error, :not_found}
      token -> {:ok, token}
    end
  end

  defp delete_email_verification_tokens_for_user(%User{id: user_id}) do
    EmailVerificationToken
    |> where([t], t.user_id == ^user_id)
    |> Repo.delete_all()

    {:ok, :deleted}
  end
end
