defmodule Ricqchet.Channels.AuthTest do
  use Ricqchet.DataCase, async: false

  alias Ricqchet.Channels.Auth
  alias Ricqchet.Channels.NamespaceCache
  alias Ricqchet.Channels.Namespaces

  setup do
    NamespaceCache.invalidate_all()
    {:ok, %{tenant: tenant, application: app}} = create_tenant_with_api_key()

    bypass = Bypass.open()

    {:ok, application} =
      app
      |> Ecto.Changeset.change(
        channels_enabled: true,
        channels_auth_endpoint: "http://localhost:#{bypass.port}/auth"
      )
      |> Ricqchet.Repo.update()

    %{tenant: tenant, application: application, bypass: bypass}
  end

  describe "authorize/4" do
    test "returns ok when auth endpoint responds 200", %{
      application: app,
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "POST", "/auth", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["channel"] == "private-chat"
        assert payload["user_id"] == "user_123"
        assert payload["socket_id"] == "socket_abc"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{user_data: %{role: "admin"}}))
      end)

      assert {:ok, auth_data} = Auth.authorize(app, "private-chat", "user_123", "socket_abc")
      assert auth_data["user_data"] == %{"role" => "admin"}
    end

    test "returns forbidden when auth endpoint responds 403", %{
      application: app,
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "POST", "/auth", fn conn ->
        Plug.Conn.resp(conn, 403, "Forbidden")
      end)

      assert {:error, :forbidden} = Auth.authorize(app, "private-room", "user_123", "socket_abc")
    end

    test "returns auth_unavailable when auth endpoint responds 500", %{
      application: app,
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "POST", "/auth", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      assert {:error, :auth_unavailable} =
               Auth.authorize(app, "private-room", "user_123", "socket_abc")
    end

    test "returns auth_unavailable when auth endpoint is down", %{
      application: app,
      bypass: bypass
    } do
      Bypass.down(bypass)

      assert {:error, :auth_unavailable} =
               Auth.authorize(app, "private-room", "user_123", "socket_abc")
    end

    test "returns no_auth_endpoint when none configured", %{tenant: tenant} do
      {:ok, created_app} =
        Ricqchet.Applications.create_application(tenant, %{name: "No Auth App"})

      app_without_endpoint =
        created_app
        |> Ecto.Changeset.change(channels_enabled: true)
        |> Ricqchet.Repo.update!()

      assert {:error, :no_auth_endpoint} =
               Auth.authorize(app_without_endpoint, "private-room", "user_123", "socket_abc")
    end

    test "uses namespace auth_endpoint when available", %{
      application: app,
      tenant: tenant
    } do
      ns_bypass = Bypass.open()

      Namespaces.create_namespace(
        %{
          pattern: "private-vip-*",
          priority: 10,
          auth_endpoint: "http://localhost:#{ns_bypass.port}/ns-auth"
        },
        app.id,
        tenant.id
      )

      Bypass.expect_once(ns_bypass, "POST", "/ns-auth", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{ok: true}))
      end)

      assert {:ok, _} = Auth.authorize(app, "private-vip-room", "user_123", "socket_abc")
    end

    test "falls back to app auth_endpoint when namespace has none", %{
      application: app,
      tenant: tenant,
      bypass: bypass
    } do
      Namespaces.create_namespace(
        %{pattern: "private-*", priority: 5},
        app.id,
        tenant.id
      )

      Bypass.expect_once(bypass, "POST", "/auth", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{ok: true}))
      end)

      assert {:ok, _} = Auth.authorize(app, "private-room", "user_123", "socket_abc")
    end
  end
end
