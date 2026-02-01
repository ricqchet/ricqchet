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
end
