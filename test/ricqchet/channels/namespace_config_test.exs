defmodule Ricqchet.Channels.NamespaceConfigTest do
  use Ricqchet.DataCase, async: false

  alias Ricqchet.Channels.NamespaceCache
  alias Ricqchet.Channels.NamespaceConfig
  alias Ricqchet.Channels.Namespaces

  setup do
    NamespaceCache.invalidate_all()
    {:ok, %{tenant: tenant, application: app}} = create_tenant_with_api_key()
    %{tenant: tenant, application: app}
  end

  describe "get_namespace_for_channel/2" do
    test "returns matching namespace from database", %{application: app, tenant: tenant} do
      {:ok, ns} =
        Namespaces.create_namespace(
          %{pattern: "private-*", priority: 10, history_enabled: true},
          app.id,
          tenant.id
        )

      assert {:ok, found} = NamespaceConfig.get_namespace_for_channel(app.id, "private-room")
      assert found.id == ns.id
      assert found.history_enabled == true
    end

    test "returns nil when no namespace matches", %{application: app, tenant: tenant} do
      Namespaces.create_namespace(
        %{pattern: "private-*", priority: 10},
        app.id,
        tenant.id
      )

      assert {:ok, nil} = NamespaceConfig.get_namespace_for_channel(app.id, "public-room")
    end

    test "caches the result on subsequent calls", %{application: app, tenant: tenant} do
      {:ok, ns} =
        Namespaces.create_namespace(
          %{pattern: "chat-*", priority: 5},
          app.id,
          tenant.id
        )

      # First call (cache miss, hits DB)
      assert {:ok, found1} = NamespaceConfig.get_namespace_for_channel(app.id, "chat-room")
      assert found1.id == ns.id

      # Verify it's now cached
      assert {:ok, found2} = NamespaceCache.get(app.id, "chat-room")
      assert found2.id == ns.id
    end

    test "caches nil results for non-matching channels", %{application: app} do
      assert {:ok, nil} = NamespaceConfig.get_namespace_for_channel(app.id, "no-match")
      assert {:ok, nil} = NamespaceCache.get(app.id, "no-match")
    end
  end

  describe "invalidate_cache/1" do
    test "clears cached entries for an application", %{application: app, tenant: tenant} do
      Namespaces.create_namespace(%{pattern: "chat-*"}, app.id, tenant.id)

      # Populate cache
      NamespaceConfig.get_namespace_for_channel(app.id, "chat-room")
      assert {:ok, _} = NamespaceCache.get(app.id, "chat-room")

      # Invalidate
      NamespaceConfig.invalidate_cache(app.id)
      assert :miss = NamespaceCache.get(app.id, "chat-room")
    end
  end
end
