defmodule Ricqchet.Auth do
  @moduledoc """
  Context module for authentication operations.

  Provides functions for user registration, login, logout, token management,
  and email verification.
  """

  import Ecto.Query

  alias Ricqchet.Auth.EmailVerificationToken
  alias Ricqchet.Auth.PasswordResetToken
  alias Ricqchet.Auth.RefreshToken
  alias Ricqchet.Auth.Token
  alias Ricqchet.Repo
  alias Ricqchet.Tenants
  alias Ricqchet.Tenants.Invitation
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

  - `:everywhere` - If true, revokes all refresh tokens and increments the
    user's token version to invalidate all sessions. Default: false.

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
        revoke_all_refresh_tokens_for_user(user)
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
  The refresh token must be valid (not expired, not revoked).

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

  Deletes any existing verification tokens for the user first, atomically.

  ## Examples

      iex> create_email_verification_token(user)
      {:ok, %EmailVerificationToken{token: "abc..."}}
  """
  def create_email_verification_token(%User{} = user) do
    Repo.transaction(fn ->
      # Delete existing tokens first
      delete_email_verification_tokens_for_user(user)

      case %EmailVerificationToken{}
           |> EmailVerificationToken.create_changeset(user)
           |> Repo.insert() do
        {:ok, token} -> token
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Requests a password reset for a user by email.

  If the email exists, creates a password reset token and returns it.
  If the email doesn't exist, returns `{:ok, nil}` to prevent email enumeration.

  ## Examples

      iex> request_password_reset("user@example.com")
      {:ok, %{user: %User{}, reset_token: "abc..."}}

      iex> request_password_reset("nonexistent@example.com")
      {:ok, nil}
  """
  def request_password_reset(email) when is_binary(email) do
    case Users.get_user_by_email(email) do
      nil ->
        # Perform dummy token generation to prevent timing attacks
        # This ensures both paths take similar time
        _ = PasswordResetToken.generate_token()
        _ = PasswordResetToken.hash_token("dummy")
        {:ok, nil}

      user ->
        case create_password_reset_token(user) do
          {:ok, token} ->
            {:ok, %{user: user, reset_token: token.token}}

          error ->
            error
        end
    end
  end

  @doc """
  Resets a user's password using a password reset token.

  Validates the token, updates the password, invalidates the token,
  and optionally invalidates all existing sessions.

  ## Examples

      iex> reset_password("reset-token", "newpassword123")
      {:ok, %User{}}

      iex> reset_password("invalid-token", "newpassword")
      {:error, :invalid_token}
  """
  def reset_password(token_string, new_password) do
    with {:ok, reset_token} <- validate_reset_token(token_string),
         {:ok, user} <- Users.update_password(reset_token.user, new_password),
         {:ok, updated_user} <- invalidate_sessions_and_cleanup(user) do
      {:ok, Repo.preload(updated_user, :tenant)}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      error -> error
    end
  end

  defp validate_reset_token(token_string) do
    with {:ok, reset_token} <- get_password_reset_token_by_token(token_string),
         true <- PasswordResetToken.valid?(reset_token) do
      {:ok, Repo.preload(reset_token, :user)}
    else
      false -> {:error, :token_expired}
      {:error, :not_found} -> {:error, :invalid_token}
    end
  end

  defp invalidate_sessions_and_cleanup(user) do
    with {:ok, updated_user} <- Users.increment_token_version(user),
         :ok <- revoke_all_refresh_tokens_for_user(user),
         {:ok, _} <- delete_password_reset_tokens_for_user(user) do
      {:ok, updated_user}
    end
  end

  @doc """
  Creates a new password reset token for a user.

  Deletes any existing reset tokens for the user first, atomically.

  ## Examples

      iex> create_password_reset_token(user)
      {:ok, %PasswordResetToken{token: "abc..."}}
  """
  def create_password_reset_token(%User{} = user) do
    Repo.transaction(fn ->
      # Delete existing tokens first
      delete_password_reset_tokens_for_user(user)

      case %PasswordResetToken{}
           |> PasswordResetToken.create_changeset(user)
           |> Repo.insert() do
        {:ok, token} -> token
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
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

  @doc """
  Changes a user's password.

  Verifies the current password, updates to the new password, increments the
  token version (invalidating all existing sessions), and returns new tokens
  for the current session.

  ## Examples

      iex> change_password(user, "current_password", "new_password123")
      {:ok, %{user: %User{}, access_token: "...", refresh_token: "...", expires_in: 900}}

      iex> change_password(user, "wrong_password", "new_password123")
      {:error, :invalid_current_password}
  """
  def change_password(%User{} = user, current_password, new_password) do
    with {:ok, _user} <- Users.change_password(user, current_password, new_password),
         {:ok, updated_user} <- Users.increment_token_version(user),
         :ok <- revoke_all_refresh_tokens_for_user(user),
         {:ok, access_token, _claims} <- Token.generate_access_token(updated_user),
         {:ok, refresh_token} <- create_refresh_token(updated_user) do
      {:ok,
       %{
         user: Repo.preload(updated_user, :tenant),
         access_token: access_token,
         refresh_token: refresh_token.token,
         expires_in: Application.get_env(:ricqchet, :jwt_access_token_ttl, 900)
       }}
    end
  end

  @doc """
  Accepts an invitation to join a tenant.

  Creates a new user account for the invited email address and returns JWT
  tokens for immediate authentication.

  Returns `{:error, :user_already_exists}` if a user with that email already
  exists in the tenant.

  ## Examples

      iex> accept_invitation("invitation-token", "password123456")
      {:ok, %{user: %User{}, access_token: "...", refresh_token: "...", expires_in: 900}}

      iex> accept_invitation("invalid-token", "password")
      {:error, :invalid_token}
  """
  def accept_invitation(token_string, password) do
    Repo.transaction(fn ->
      with {:ok, invitation} <- get_and_validate_invitation(token_string),
           {:ok, user} <- create_user_from_invitation(invitation, password),
           {:ok, _} <- Tenants.accept_invitation(invitation),
           {:ok, auth_data} <- generate_auth_tokens(user) do
        auth_data
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp get_and_validate_invitation(token_string) do
    with {:ok, invitation} <- get_invitation_by_token(token_string),
         :ok <- validate_invitation(invitation),
         invitation <- Repo.preload(invitation, :tenant),
         :ok <- check_user_does_not_exist(invitation) do
      {:ok, invitation}
    end
  end

  # Private functions

  defp verify_email_confirmed(%User{confirmed_at: nil}), do: {:error, :email_not_verified}
  defp verify_email_confirmed(%User{}), do: :ok

  defp generate_auth_tokens(%User{} = user) do
    with {:ok, access_token, _claims} <- Token.generate_access_token(user),
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

  defp get_password_reset_token_by_token(token_string) when is_binary(token_string) do
    token_hash = PasswordResetToken.hash_token(token_string)

    result =
      PasswordResetToken
      |> where([t], t.token_hash == ^token_hash)
      |> Repo.one()

    case result do
      nil -> {:error, :not_found}
      token -> {:ok, token}
    end
  end

  defp delete_password_reset_tokens_for_user(%User{id: user_id}) do
    PasswordResetToken
    |> where([t], t.user_id == ^user_id)
    |> Repo.delete_all()

    {:ok, :deleted}
  end

  defp get_invitation_by_token(token_string) when is_binary(token_string) do
    case Tenants.get_invitation_by_token(token_string) do
      nil -> {:error, :invalid_token}
      invitation -> {:ok, invitation}
    end
  end

  defp validate_invitation(%Invitation{status: "pending"} = invitation) do
    if Invitation.expired?(invitation) do
      {:error, :token_expired}
    else
      :ok
    end
  end

  defp validate_invitation(%Invitation{}), do: {:error, :invitation_not_pending}

  defp check_user_does_not_exist(%Invitation{} = invitation) do
    case Users.get_user_by_email_and_tenant(invitation.email, invitation.tenant) do
      nil -> :ok
      %User{} -> {:error, :user_already_exists}
    end
  end

  defp create_user_from_invitation(%Invitation{} = invitation, password) do
    # Create a new user with the invitation's email and role
    # User is automatically confirmed since they received the invitation email
    user_attrs = %{
      "email" => invitation.email,
      "password" => password,
      "role" => invitation.role,
      "status" => "active"
    }

    %User{}
    |> User.registration_changeset(invitation.tenant, user_attrs)
    |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now())
    |> Repo.insert()
  end
end
