defmodule Ricqchet.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Ricqchet.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Ricqchet.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Ricqchet.DataCase

      use Oban.Testing, repo: Ricqchet.Repo
    end
  end

  setup tags do
    Ricqchet.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Ricqchet.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts
        |> Keyword.get(String.to_existing_atom(key), key)
        |> to_string()
      end)
    end)
  end

  @doc """
  Creates a tenant with an application and API key for testing.

  Returns `{:ok, %{tenant: tenant, application: application, api_key: api_key}}`
  where `api_key` has the plaintext key in its virtual field.

  ## Examples

      {:ok, %{tenant: tenant, api_key: api_key}} = create_tenant_with_api_key()
      # Use api_key.api_key for the Bearer token

  """
  def create_tenant_with_api_key(tenant_attrs \\ %{}, app_attrs \\ %{}, key_attrs \\ %{}) do
    alias Ricqchet.ApiKeys
    alias Ricqchet.Applications
    alias Ricqchet.Tenants

    tenant_attrs = Map.put_new(tenant_attrs, :name, "Test Tenant")
    app_attrs = Map.put_new(app_attrs, :name, "Test Application")
    key_attrs = Map.put_new(key_attrs, :name, "Test API Key")

    {:ok, tenant} = Tenants.create_tenant(tenant_attrs)
    {:ok, application} = Applications.create_application(tenant, app_attrs)
    {:ok, api_key} = ApiKeys.create_api_key(application, key_attrs)

    {:ok, %{tenant: tenant, application: application, api_key: api_key}}
  end

  @doc """
  Creates a tenant and a confirmed user for controller/LiveView tests.

  Replaces the old `Auth.register_user` + `Auth.verify_email` setup pattern now
  that self-sign-up has been removed. The user is created active and confirmed,
  ready to authenticate. Pass `:tenant` to attach the user to an existing org
  (e.g. to add a second user with a different role to the same tenant).

  Returns `{:ok, %{user: user, tenant: tenant}}` with the tenant preloaded.

  ## Options

    * `:email` - defaults to a unique address
    * `:password` - defaults to "secure_password_123"
    * `:role` - defaults to "admin"
    * `:tenant_name` - defaults to a unique name (ignored when `:tenant` is given)
    * `:tenant` - an existing `%Tenant{}` to attach the user to

  ## Examples

      {:ok, %{user: admin, tenant: tenant}} = create_tenant_and_user()
      {:ok, %{user: viewer}} = create_tenant_and_user(tenant: tenant, role: "viewer")

  """
  def create_tenant_and_user(opts \\ []) do
    alias Ricqchet.Tenants
    alias Ricqchet.Users

    unique = System.unique_integer([:positive])
    email = Keyword.get(opts, :email, "user#{unique}@example.com")
    password = Keyword.get(opts, :password, "secure_password_123")
    role = Keyword.get(opts, :role, "admin")

    tenant =
      case Keyword.get(opts, :tenant) do
        nil ->
          name = Keyword.get(opts, :tenant_name, "Test Org #{unique}")
          {:ok, tenant} = Tenants.create_tenant(%{name: name})
          tenant

        %{} = tenant ->
          tenant
      end

    {:ok, user, _password} =
      Users.create_user_by_admin(tenant, %{
        "email" => email,
        "password" => password,
        "role" => role
      })

    {:ok, %{user: Ricqchet.Repo.preload(user, :tenant), tenant: tenant}}
  end

  @doc """
  Generates a JWT access token for a user (test convenience).
  """
  def access_token_for(user) do
    alias Ricqchet.Auth.Token

    {:ok, token, _claims} = Token.generate_access_token(user)
    token
  end
end
