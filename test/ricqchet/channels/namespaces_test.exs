defmodule Ricqchet.Channels.NamespacesTest do
  use Ricqchet.DataCase, async: true

  alias Ricqchet.Channels.Namespaces

  setup do
    {:ok, %{tenant: tenant, application: app}} = create_tenant_with_api_key()
    %{tenant: tenant, application: app}
  end

  describe "create_namespace/3" do
    test "creates a namespace with valid attrs", %{application: app, tenant: tenant} do
      attrs = %{pattern: "private-chat-*", priority: 10, history_enabled: true}

      assert {:ok, namespace} = Namespaces.create_namespace(attrs, app.id, tenant.id)
      assert namespace.pattern == "private-chat-*"
      assert namespace.priority == 10
      assert namespace.history_enabled == true
      assert namespace.application_id == app.id
      assert namespace.tenant_id == tenant.id
    end

    test "creates a catch-all namespace", %{application: app, tenant: tenant} do
      attrs = %{pattern: "*", priority: 0}
      assert {:ok, namespace} = Namespaces.create_namespace(attrs, app.id, tenant.id)
      assert namespace.pattern == "*"
    end

    test "creates a namespace with all config fields", %{application: app, tenant: tenant} do
      attrs = %{
        pattern: "lobby-*",
        priority: 5,
        history_enabled: true,
        history_ttl_seconds: 3600,
        history_max_events: 100,
        cache_enabled: true,
        max_members: 500,
        max_event_size_bytes: 10_000,
        max_client_events_per_second: 10,
        auth_endpoint: "https://example.com/auth",
        webhook_url: "https://example.com/webhook"
      }

      assert {:ok, namespace} = Namespaces.create_namespace(attrs, app.id, tenant.id)
      assert namespace.history_ttl_seconds == 3600
      assert namespace.history_max_events == 100
      assert namespace.max_members == 500
      assert namespace.auth_endpoint == "https://example.com/auth"
    end

    test "fails without required pattern", %{application: app, tenant: tenant} do
      assert {:error, changeset} = Namespaces.create_namespace(%{}, app.id, tenant.id)
      assert errors_on(changeset).pattern
    end

    test "fails with duplicate pattern for same application", %{
      application: app,
      tenant: tenant
    } do
      attrs = %{pattern: "chat-*", priority: 1}
      assert {:ok, _} = Namespaces.create_namespace(attrs, app.id, tenant.id)
      assert {:error, changeset} = Namespaces.create_namespace(attrs, app.id, tenant.id)
      assert errors_on(changeset).application_id
    end

    test "allows same pattern for different applications", %{
      application: app,
      tenant: tenant
    } do
      {:ok, app2} =
        Ricqchet.Applications.create_application(tenant, %{name: "Second App"})

      attrs = %{pattern: "chat-*", priority: 1}
      assert {:ok, _} = Namespaces.create_namespace(attrs, app.id, tenant.id)
      assert {:ok, _} = Namespaces.create_namespace(attrs, app2.id, tenant.id)
    end

    test "validates numeric fields", %{application: app, tenant: tenant} do
      attrs = %{pattern: "test", history_ttl_seconds: 0}
      assert {:error, changeset} = Namespaces.create_namespace(attrs, app.id, tenant.id)
      assert errors_on(changeset).history_ttl_seconds

      attrs = %{pattern: "test", max_members: -1}
      assert {:error, changeset} = Namespaces.create_namespace(attrs, app.id, tenant.id)
      assert errors_on(changeset).max_members
    end

    test "validates pattern length", %{application: app, tenant: tenant} do
      long_pattern = String.duplicate("a", 256)
      attrs = %{pattern: long_pattern}
      assert {:error, changeset} = Namespaces.create_namespace(attrs, app.id, tenant.id)
      assert errors_on(changeset).pattern
    end
  end

  describe "list_namespaces/1" do
    test "returns namespaces ordered by priority descending", %{
      application: app,
      tenant: tenant
    } do
      Namespaces.create_namespace(%{pattern: "low-*", priority: 1}, app.id, tenant.id)
      Namespaces.create_namespace(%{pattern: "high-*", priority: 10}, app.id, tenant.id)
      Namespaces.create_namespace(%{pattern: "mid-*", priority: 5}, app.id, tenant.id)

      namespaces = Namespaces.list_namespaces(app.id)
      priorities = Enum.map(namespaces, & &1.priority)
      assert priorities == [10, 5, 1]
    end

    test "returns empty list when no namespaces exist", %{application: app} do
      assert Namespaces.list_namespaces(app.id) == []
    end

    test "scopes to application", %{tenant: tenant, application: app} do
      {:ok, app2} =
        Ricqchet.Applications.create_application(tenant, %{name: "Other App"})

      Namespaces.create_namespace(%{pattern: "app1-*"}, app.id, tenant.id)
      Namespaces.create_namespace(%{pattern: "app2-*"}, app2.id, tenant.id)

      namespaces = Namespaces.list_namespaces(app.id)
      assert length(namespaces) == 1
      assert hd(namespaces).pattern == "app1-*"
    end
  end

  describe "get_namespace/2" do
    test "returns namespace by id scoped to application", %{
      application: app,
      tenant: tenant
    } do
      {:ok, created} =
        Namespaces.create_namespace(%{pattern: "test-*"}, app.id, tenant.id)

      assert found = Namespaces.get_namespace(created.id, app.id)
      assert found.id == created.id
    end

    test "returns nil for wrong application", %{application: app, tenant: tenant} do
      {:ok, app2} =
        Ricqchet.Applications.create_application(tenant, %{name: "Other App"})

      {:ok, created} =
        Namespaces.create_namespace(%{pattern: "test-*"}, app.id, tenant.id)

      assert Namespaces.get_namespace(created.id, app2.id) == nil
    end

    test "returns nil for non-existent id", %{application: app} do
      assert Namespaces.get_namespace(Ecto.UUID.generate(), app.id) == nil
    end
  end

  describe "update_namespace/2" do
    test "updates namespace fields", %{application: app, tenant: tenant} do
      {:ok, namespace} =
        Namespaces.create_namespace(%{pattern: "old-*", priority: 1}, app.id, tenant.id)

      assert {:ok, updated} =
               Namespaces.update_namespace(namespace, %{priority: 10, history_enabled: true})

      assert updated.priority == 10
      assert updated.history_enabled == true
      assert updated.pattern == "old-*"
    end

    test "validates on update", %{application: app, tenant: tenant} do
      {:ok, namespace} =
        Namespaces.create_namespace(%{pattern: "test-*"}, app.id, tenant.id)

      assert {:error, changeset} =
               Namespaces.update_namespace(namespace, %{history_ttl_seconds: 0})

      assert errors_on(changeset).history_ttl_seconds
    end
  end

  describe "delete_namespace/1" do
    test "deletes a namespace", %{application: app, tenant: tenant} do
      {:ok, namespace} =
        Namespaces.create_namespace(%{pattern: "delete-me"}, app.id, tenant.id)

      assert {:ok, _} = Namespaces.delete_namespace(namespace)
      assert Namespaces.get_namespace(namespace.id, app.id) == nil
    end
  end

  describe "find_matching_namespace/2" do
    test "matches exact pattern", %{application: app, tenant: tenant} do
      Namespaces.create_namespace(%{pattern: "chat-room1", priority: 5}, app.id, tenant.id)

      assert ns = Namespaces.find_matching_namespace(app.id, "chat-room1")
      assert ns.pattern == "chat-room1"
    end

    test "does not match exact pattern to different name", %{
      application: app,
      tenant: tenant
    } do
      Namespaces.create_namespace(%{pattern: "chat-room1", priority: 5}, app.id, tenant.id)
      assert Namespaces.find_matching_namespace(app.id, "chat-room2") == nil
    end

    test "matches prefix wildcard", %{application: app, tenant: tenant} do
      Namespaces.create_namespace(
        %{pattern: "private-chat-*", priority: 5},
        app.id,
        tenant.id
      )

      assert ns = Namespaces.find_matching_namespace(app.id, "private-chat-room1")
      assert ns.pattern == "private-chat-*"
    end

    test "prefix wildcard does not match shorter name", %{
      application: app,
      tenant: tenant
    } do
      Namespaces.create_namespace(
        %{pattern: "private-chat-*", priority: 5},
        app.id,
        tenant.id
      )

      assert Namespaces.find_matching_namespace(app.id, "private-cha") == nil
    end

    test "matches catch-all wildcard", %{application: app, tenant: tenant} do
      Namespaces.create_namespace(%{pattern: "*", priority: 0}, app.id, tenant.id)

      assert ns = Namespaces.find_matching_namespace(app.id, "anything-at-all")
      assert ns.pattern == "*"
    end

    test "returns highest priority match", %{application: app, tenant: tenant} do
      Namespaces.create_namespace(%{pattern: "*", priority: 0}, app.id, tenant.id)

      Namespaces.create_namespace(
        %{pattern: "private-*", priority: 10},
        app.id,
        tenant.id
      )

      assert ns = Namespaces.find_matching_namespace(app.id, "private-room")
      assert ns.pattern == "private-*"
      assert ns.priority == 10
    end

    test "falls back to lower priority when high priority does not match", %{
      application: app,
      tenant: tenant
    } do
      Namespaces.create_namespace(
        %{pattern: "private-*", priority: 10},
        app.id,
        tenant.id
      )

      Namespaces.create_namespace(%{pattern: "*", priority: 0}, app.id, tenant.id)

      assert ns = Namespaces.find_matching_namespace(app.id, "public-room")
      assert ns.pattern == "*"
    end

    test "returns nil when no namespace matches", %{application: app, tenant: tenant} do
      Namespaces.create_namespace(
        %{pattern: "private-*", priority: 10},
        app.id,
        tenant.id
      )

      assert Namespaces.find_matching_namespace(app.id, "public-room") == nil
    end
  end

  describe "pattern_matches?/2" do
    test "catch-all matches everything" do
      assert Namespaces.pattern_matches?("*", "anything")
      assert Namespaces.pattern_matches?("*", "")
    end

    test "prefix wildcard matches prefix" do
      assert Namespaces.pattern_matches?("private-*", "private-room")
      assert Namespaces.pattern_matches?("private-*", "private-")
      refute Namespaces.pattern_matches?("private-*", "public-room")
    end

    test "exact match" do
      assert Namespaces.pattern_matches?("chat-room1", "chat-room1")
      refute Namespaces.pattern_matches?("chat-room1", "chat-room2")
      refute Namespaces.pattern_matches?("chat-room1", "chat-room1-extra")
    end
  end
end
