defmodule RicqchetWeb.ChannelNamespaceControllerTest do
  use RicqchetWeb.ConnCase, async: false

  alias Ricqchet.Applications
  alias Ricqchet.Auth
  alias Ricqchet.Auth.Token
  alias Ricqchet.Channels.Namespaces
  alias Ricqchet.Repo

  setup %{conn: conn} do
    {:ok, %{user: _user, verification_token: token}} =
      Auth.register_user(%{
        "email" => "admin#{System.unique_integer()}@example.com",
        "password" => "secure_password_123",
        "tenant_name" => "Test Org #{System.unique_integer()}"
      })

    {:ok, verified_user} = Auth.verify_email(token)
    {:ok, access_token, _claims} = Token.generate_access_token(verified_user)

    user = Repo.preload(verified_user, :tenant)
    tenant = user.tenant

    {:ok, application} = Applications.create_application(tenant, %{name: "Test Application"})

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{access_token}")
      |> put_req_header("content-type", "application/json")

    %{conn: conn, user: user, tenant: tenant, application: application}
  end

  describe "GET /v1/applications/:app_id/channel-namespaces" do
    test "lists namespaces for application", %{conn: conn, application: app, tenant: tenant} do
      Namespaces.create_namespace(%{pattern: "private-*", priority: 10}, app.id, tenant.id)
      Namespaces.create_namespace(%{pattern: "*", priority: 0}, app.id, tenant.id)

      conn = get(conn, "/v1/applications/#{app.id}/channel-namespaces")
      response = json_response(conn, 200)

      assert length(response["data"]) == 2
      patterns = Enum.map(response["data"], & &1["pattern"])
      assert "private-*" in patterns
      assert "*" in patterns
    end

    test "returns empty list when no namespaces exist", %{conn: conn, application: app} do
      conn = get(conn, "/v1/applications/#{app.id}/channel-namespaces")
      assert %{"data" => []} = json_response(conn, 200)
    end

    test "returns 404 for non-existent application", %{conn: conn} do
      conn = get(conn, "/v1/applications/#{Ecto.UUID.generate()}/channel-namespaces")
      assert json_response(conn, 404)
    end

    test "returns 401 without auth" do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> get("/v1/applications/#{Ecto.UUID.generate()}/channel-namespaces")

      assert json_response(conn, 401)
    end
  end

  describe "POST /v1/applications/:app_id/channel-namespaces" do
    test "creates a namespace", %{conn: conn, application: app} do
      params = %{
        "pattern" => "private-chat-*",
        "priority" => 10,
        "history_enabled" => true,
        "history_max_events" => 1000,
        "auth_endpoint" => "https://example.com/auth"
      }

      conn = post(conn, "/v1/applications/#{app.id}/channel-namespaces", params)
      response = json_response(conn, 201)

      assert response["data"]["pattern"] == "private-chat-*"
      assert response["data"]["priority"] == 10
      assert response["data"]["history_enabled"] == true
      assert response["data"]["history_max_events"] == 1000
      assert response["data"]["auth_endpoint"] == "https://example.com/auth"
      assert response["data"]["id"]
    end

    test "returns 422 for invalid pattern", %{conn: conn, application: app} do
      conn = post(conn, "/v1/applications/#{app.id}/channel-namespaces", %{})
      assert json_response(conn, 422)
    end

    test "returns 409 for duplicate pattern", %{conn: conn, application: app, tenant: tenant} do
      Namespaces.create_namespace(%{pattern: "chat-*"}, app.id, tenant.id)

      conn =
        post(conn, "/v1/applications/#{app.id}/channel-namespaces", %{"pattern" => "chat-*"})

      assert json_response(conn, 422)
    end

    test "returns 403 for non-admin user", %{tenant: tenant, application: app} do
      {:ok, member} =
        Ricqchet.Users.create_user(tenant, %{
          email: "member#{System.unique_integer()}@example.com",
          password: "secure_password_123",
          role: "member"
        })

      {:ok, member_token, _claims} = Token.generate_access_token(member)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{member_token}")
        |> put_req_header("content-type", "application/json")
        |> post("/v1/applications/#{app.id}/channel-namespaces", %{"pattern" => "test-*"})

      assert json_response(conn, 403)
    end
  end

  describe "PATCH /v1/applications/:app_id/channel-namespaces/:id" do
    test "updates a namespace", %{conn: conn, application: app, tenant: tenant} do
      {:ok, namespace} =
        Namespaces.create_namespace(%{pattern: "chat-*", priority: 1}, app.id, tenant.id)

      params = %{"priority" => 20, "history_enabled" => true}

      conn =
        patch(conn, "/v1/applications/#{app.id}/channel-namespaces/#{namespace.id}", params)

      response = json_response(conn, 200)
      assert response["data"]["priority"] == 20
      assert response["data"]["history_enabled"] == true
      assert response["data"]["pattern"] == "chat-*"
    end

    test "returns 404 for non-existent namespace", %{conn: conn, application: app} do
      conn =
        patch(
          conn,
          "/v1/applications/#{app.id}/channel-namespaces/#{Ecto.UUID.generate()}",
          %{"priority" => 5}
        )

      assert json_response(conn, 404)
    end

    test "returns 422 for invalid values", %{conn: conn, application: app, tenant: tenant} do
      {:ok, namespace} =
        Namespaces.create_namespace(%{pattern: "chat-*"}, app.id, tenant.id)

      conn =
        patch(conn, "/v1/applications/#{app.id}/channel-namespaces/#{namespace.id}", %{
          "history_ttl_seconds" => 0
        })

      assert json_response(conn, 422)
    end
  end

  describe "DELETE /v1/applications/:app_id/channel-namespaces/:id" do
    test "deletes a namespace", %{conn: conn, application: app, tenant: tenant} do
      {:ok, namespace} =
        Namespaces.create_namespace(%{pattern: "delete-me"}, app.id, tenant.id)

      conn = delete(conn, "/v1/applications/#{app.id}/channel-namespaces/#{namespace.id}")
      assert response(conn, 204)

      assert Namespaces.get_namespace(namespace.id, app.id) == nil
    end

    test "returns 404 for non-existent namespace", %{conn: conn, application: app} do
      conn =
        delete(conn, "/v1/applications/#{app.id}/channel-namespaces/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)
    end
  end
end
