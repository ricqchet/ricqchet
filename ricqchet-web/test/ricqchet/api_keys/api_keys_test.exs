defmodule Ricqchet.ApiKeysTest do
  use Ricqchet.DataCase, async: true

  alias Ricqchet.ApiKeys

  setup do
    {:ok, %{application: application}} = create_tenant_with_api_key()
    %{application: application}
  end

  describe "create_api_key/2 scope" do
    test "defaults to relay when scope is omitted", %{application: app} do
      assert {:ok, key} = ApiKeys.create_api_key(app, %{name: "Default"})
      assert key.scope == "relay"
    end

    test "creates a subscribe-scoped key", %{application: app} do
      assert {:ok, key} = ApiKeys.create_api_key(app, %{name: "Browser", scope: "subscribe"})
      assert key.scope == "subscribe"
    end

    test "rejects an unknown scope", %{application: app} do
      assert {:error, changeset} = ApiKeys.create_api_key(app, %{name: "Bad", scope: "god"})
      assert "is invalid" in errors_on(changeset).scope
    end
  end

  describe "rotate_api_key/1 preserves scope" do
    test "a rotated subscribe key stays subscribe", %{application: app} do
      {:ok, key} = ApiKeys.create_api_key(app, %{name: "Browser", scope: "subscribe"})

      assert {:ok, {revoked, rotated}} = ApiKeys.rotate_api_key(key)
      assert revoked.status == "revoked"
      assert rotated.scope == "subscribe"
      assert rotated.id != key.id
    end

    test "a rotated relay key stays relay", %{application: app} do
      {:ok, key} = ApiKeys.create_api_key(app, %{name: "Server", scope: "relay"})

      assert {:ok, {_revoked, rotated}} = ApiKeys.rotate_api_key(key)
      assert rotated.scope == "relay"
    end
  end
end
