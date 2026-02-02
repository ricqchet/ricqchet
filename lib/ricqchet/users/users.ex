defmodule Ricqchet.Users do
  @moduledoc """
  Context module for user management and authentication.
  """

  import Ecto.Query

  alias Ricqchet.Repo
  alias Ricqchet.Tenants.Tenant
  alias Ricqchet.Users.User

  @doc """
  Creates a new user for a tenant.

  ## Examples

      iex> create_user(tenant, %{email: "admin@example.com", password: "secure_password"})
      {:ok, %User{}}

  """
  def create_user(%Tenant{} = tenant, attrs \\ %{}) do
    %User{}
    |> User.registration_changeset(tenant, attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a user by ID.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Gets a user by ID, raising if not found.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a user by email address.
  """
  def get_user_by_email(email) when is_binary(email) do
    User
    |> where([u], u.email == ^email)
    |> Repo.one()
  end

  @doc """
  Gets a user by email, scoped to a tenant.
  """
  def get_user_by_email_and_tenant(email, %Tenant{id: tenant_id}) when is_binary(email) do
    User
    |> where([u], u.email == ^email and u.tenant_id == ^tenant_id)
    |> Repo.one()
  end

  @doc """
  Authenticates a user by email and password.

  Only authenticates users with `status: "active"`.
  Returns `{:ok, user}` on success or `{:error, :invalid_credentials}` on failure.

  ## Examples

      iex> authenticate_user("user@example.com", "correct_password")
      {:ok, %User{}}

      iex> authenticate_user("user@example.com", "wrong_password")
      {:error, :invalid_credentials}

  """
  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    verify_password(user, password)
  end

  @doc """
  Authenticates a user for a given tenant by email and password.

  Only authenticates users with `status: "active"`.
  Returns `{:ok, user}` on success or `{:error, :invalid_credentials}` on failure.

  ## Examples

      iex> authenticate_user(tenant, "user@example.com", "correct_password")
      {:ok, %User{}}

      iex> authenticate_user(tenant, "user@example.com", "wrong_password")
      {:error, :invalid_credentials}

  """
  def authenticate_user(%Tenant{} = tenant, email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email_and_tenant(email, tenant)
    verify_password(user, password)
  end

  @doc """
  Lists all users for a tenant.
  """
  def list_users_for_tenant(%Tenant{id: tenant_id}) do
    User
    |> where([u], u.tenant_id == ^tenant_id)
    |> order_by([u], desc: u.inserted_at)
    |> Repo.all()
  end

  @doc """
  Updates a user.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Changes a user's password.
  """
  def change_password(%User{} = user, current_password, new_password) do
    case verify_password(user, current_password) do
      {:ok, _user} ->
        user
        |> User.password_changeset(%{password: new_password})
        |> Repo.update()

      {:error, :invalid_credentials} ->
        {:error, :invalid_current_password}
    end
  end

  @doc """
  Updates a user's password directly (without requiring current password).

  Used for password reset flows where the user has verified identity via token.
  """
  def update_password(%User{} = user, new_password) do
    user
    |> User.password_changeset(%{password: new_password})
    |> Repo.update()
  end

  @doc """
  Updates the last_login_at timestamp for a user.
  """
  def touch_last_login(%User{} = user) do
    user
    |> User.login_changeset()
    |> Repo.update()
  end

  @doc """
  Confirms a user's email address.
  """
  def confirm_user(%User{} = user) do
    user
    |> User.confirm_changeset()
    |> Repo.update()
  end

  @doc """
  Increments the user's token version, invalidating all existing JWT tokens.

  This is used to log out a user from all sessions (e.g., on password change).
  """
  def increment_token_version(%User{} = user) do
    user
    |> User.increment_token_version_changeset()
    |> Repo.update()
  end

  # Always perform the hash comparison to ensure constant timing
  defp verify_password(nil, _password) do
    # Perform a dummy verification to prevent timing attacks
    Argon2.no_user_verify()
    {:error, :invalid_credentials}
  end

  defp verify_password(%User{status: status} = user, password)
       when status in ["active", "pending"] do
    if Argon2.verify_pass(password, user.password_hash) do
      {:ok, user}
    else
      {:error, :invalid_credentials}
    end
  end

  defp verify_password(%User{}, _password) do
    # User exists but is suspended
    {:error, :invalid_credentials}
  end
end
