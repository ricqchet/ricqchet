defmodule RicqchetWeb.TenantControllerTest do
  use RicqchetWeb.ConnCase, async: false

  describe "GET /v1/tenant" do
    setup do
      {:ok, %{user: admin, tenant: tenant}} =
        create_tenant_and_user(
          email: "admin@tenant-test.com",
          password: "secure_password_123",
          tenant_name: "Tenant Test Org"
        )

      admin_token = access_token_for(admin)

      # Create a member user
      {:ok, %{user: member}} = create_tenant_and_user(tenant: tenant, role: "member")
      member_token = access_token_for(member)

      # Create a viewer user
      {:ok, %{user: viewer}} = create_tenant_and_user(tenant: tenant, role: "viewer")
      viewer_token = access_token_for(viewer)

      %{
        admin: admin,
        admin_token: admin_token,
        member: member,
        member_token: member_token,
        viewer: viewer,
        viewer_token: viewer_token,
        tenant: tenant
      }
    end

    test "returns tenant details for admin with signing_secret", %{
      conn: conn,
      tenant: tenant,
      admin_token: token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/v1/tenant")

      response = json_response(conn, 200)

      assert response["id"] == tenant.id
      assert response["name"] == "Tenant Test Org"
      assert response["status"] == "active"
      assert response["default_max_retries"] == 3
      assert response["signing_secret"]
      assert response["inserted_at"]
      assert response["updated_at"]
    end

    test "returns tenant details for member without signing_secret", %{
      conn: conn,
      tenant: tenant,
      member_token: token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/v1/tenant")

      response = json_response(conn, 200)

      assert response["id"] == tenant.id
      assert response["name"] == "Tenant Test Org"
      refute response["signing_secret"]
    end

    test "returns tenant details for viewer without signing_secret", %{
      conn: conn,
      tenant: tenant,
      viewer_token: token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/v1/tenant")

      response = json_response(conn, 200)

      assert response["id"] == tenant.id
      assert response["name"] == "Tenant Test Org"
      refute response["signing_secret"]
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> get("/v1/tenant")

      assert json_response(conn, 401)
    end
  end

  describe "PATCH /v1/tenant" do
    setup do
      {:ok, %{user: admin, tenant: tenant}} =
        create_tenant_and_user(
          email: "admin@patch-test.com",
          password: "secure_password_123",
          tenant_name: "Patch Test Org"
        )

      admin_token = access_token_for(admin)

      # Create a member user
      {:ok, %{user: member}} = create_tenant_and_user(tenant: tenant, role: "member")
      member_token = access_token_for(member)

      # Create a viewer user
      {:ok, %{user: viewer}} = create_tenant_and_user(tenant: tenant, role: "viewer")
      viewer_token = access_token_for(viewer)

      %{
        admin: admin,
        admin_token: admin_token,
        member: member,
        member_token: member_token,
        viewer: viewer,
        viewer_token: viewer_token,
        tenant: tenant
      }
    end

    test "admin can update tenant name", %{
      conn: conn,
      admin_token: token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/v1/tenant", %{"name" => "Updated Org Name"})

      response = json_response(conn, 200)

      assert response["name"] == "Updated Org Name"
    end

    test "admin can update default_max_retries", %{
      conn: conn,
      admin_token: token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/v1/tenant", %{"default_max_retries" => 5})

      response = json_response(conn, 200)

      assert response["default_max_retries"] == 5
    end

    test "member cannot update tenant", %{
      conn: conn,
      member_token: token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/v1/tenant", %{"name" => "Should Not Work"})

      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "viewer cannot update tenant", %{
      conn: conn,
      viewer_token: token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/v1/tenant", %{"name" => "Should Not Work"})

      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/v1/tenant", %{"name" => "No Auth"})

      assert json_response(conn, 401)
    end
  end
end
