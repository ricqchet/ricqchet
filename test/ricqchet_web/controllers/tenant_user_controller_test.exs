defmodule RicqchetWeb.TenantUserControllerTest do
  use RicqchetWeb.ConnCase, async: false

  alias Ricqchet.Users

  describe "GET /v1/tenant/users" do
    setup do
      {:ok, %{user: admin, tenant: tenant}} =
        create_tenant_and_user(email: "admin@users-test.com")

      admin_token = access_token_for(admin)

      {:ok, %{user: _member}} =
        create_tenant_and_user(tenant: tenant, email: "member@users-test.com", role: "member")

      {:ok, %{user: _viewer}} =
        create_tenant_and_user(tenant: tenant, email: "viewer@users-test.com", role: "viewer")

      %{admin: admin, admin_token: admin_token, tenant: tenant}
    end

    test "lists all users in tenant", %{conn: conn, admin_token: token} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/v1/tenant/users")

      response = json_response(conn, 200)

      assert response["meta"]["total"] == 3
      assert length(response["data"]) == 3

      emails = Enum.map(response["data"], & &1["email"])
      assert "admin@users-test.com" in emails
      assert "member@users-test.com" in emails
      assert "viewer@users-test.com" in emails
    end

    test "supports pagination", %{conn: conn, admin_token: token} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/v1/tenant/users?limit=2")

      response = json_response(conn, 200)

      assert response["meta"]["total"] == 3
      assert length(response["data"]) == 2
      assert response["meta"]["has_next_page"] == true
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> get("/v1/tenant/users")

      assert json_response(conn, 401)
    end
  end

  describe "POST /v1/tenant/users" do
    setup do
      {:ok, %{user: admin, tenant: tenant}} =
        create_tenant_and_user(email: "admin@create-test.com")

      admin_token = access_token_for(admin)

      {:ok, %{user: member}} =
        create_tenant_and_user(tenant: tenant, email: "member@create-test.com", role: "member")

      member_token = access_token_for(member)

      %{admin: admin, admin_token: admin_token, member_token: member_token, tenant: tenant}
    end

    test "admin can create a user with a generated password", %{conn: conn, admin_token: token} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/v1/tenant/users", %{"email" => "newuser@example.com", "role" => "member"})

      response = json_response(conn, 201)

      assert response["email"] == "newuser@example.com"
      assert response["role"] == "member"
      assert response["status"] == "active"
      # A one-time password is generated and returned when none is supplied
      assert is_binary(response["password"])
    end

    test "admin can create a user with a supplied password (not echoed)", %{
      conn: conn,
      admin_token: token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/v1/tenant/users", %{
          "email" => "supplied@example.com",
          "role" => "viewer",
          "password" => "supplied_password_123"
        })

      response = json_response(conn, 201)

      assert response["email"] == "supplied@example.com"
      assert response["role"] == "viewer"
      refute Map.has_key?(response, "password")
    end

    test "member cannot create users", %{conn: conn, member_token: token} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/v1/tenant/users", %{"email" => "newuser@example.com", "role" => "member"})

      assert json_response(conn, 403)
    end

    test "returns 409 for duplicate email", %{conn: conn, admin_token: token} do
      # First creation
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/v1/tenant/users", %{"email" => "duplicate@example.com", "role" => "member"})

      # Second creation with the same email
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/v1/tenant/users", %{"email" => "duplicate@example.com", "role" => "member"})

      response = json_response(conn, 409)
      assert response["error"] == "user_already_exists"
    end

    test "returns 422 for invalid params", %{conn: conn, admin_token: token} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/v1/tenant/users", %{"email" => "not-an-email", "role" => "member"})

      assert json_response(conn, 422)
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/tenant/users", %{"email" => "newuser@example.com", "role" => "member"})

      assert json_response(conn, 401)
    end
  end

  describe "PATCH /v1/tenant/users/:id" do
    setup do
      {:ok, %{user: admin, tenant: tenant}} = create_tenant_and_user(email: "admin@role-test.com")
      admin_token = access_token_for(admin)

      {:ok, %{user: admin2}} =
        create_tenant_and_user(tenant: tenant, email: "admin2@role-test.com", role: "admin")

      {:ok, %{user: member}} =
        create_tenant_and_user(tenant: tenant, email: "member@role-test.com", role: "member")

      member_token = access_token_for(member)

      %{
        admin: admin,
        admin2: admin2,
        admin_token: admin_token,
        member: member,
        member_token: member_token,
        tenant: tenant
      }
    end

    test "admin can update user role", %{conn: conn, admin_token: token, member: member} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/v1/tenant/users/#{member.id}", %{"role" => "admin"})

      response = json_response(conn, 200)

      assert response["role"] == "admin"
    end

    test "admin can demote self if not last admin", %{
      conn: conn,
      admin_token: token,
      admin: admin
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/v1/tenant/users/#{admin.id}", %{"role" => "member"})

      response = json_response(conn, 200)

      assert response["role"] == "member"
    end

    test "member cannot update roles", %{conn: conn, member_token: token, admin: admin} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/v1/tenant/users/#{admin.id}", %{"role" => "viewer"})

      assert json_response(conn, 403)
    end

    test "returns 404 for non-existent user", %{conn: conn, admin_token: token} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/v1/tenant/users/#{fake_id}", %{"role" => "member"})

      assert json_response(conn, 404)
    end

    test "returns 401 without authentication", %{conn: conn, member: member} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/v1/tenant/users/#{member.id}", %{"role" => "admin"})

      assert json_response(conn, 401)
    end
  end

  describe "PATCH /v1/tenant/users/:id - last admin protection" do
    setup do
      {:ok, %{user: admin}} = create_tenant_and_user(email: "only-admin@test.com")
      admin_token = access_token_for(admin)

      %{admin: admin, admin_token: admin_token}
    end

    test "cannot demote last admin", %{conn: conn, admin_token: token, admin: admin} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/v1/tenant/users/#{admin.id}", %{"role" => "member"})

      response = json_response(conn, 403)
      assert response["message"] =~ "last admin"
    end
  end

  describe "DELETE /v1/tenant/users/:id" do
    setup do
      {:ok, %{user: admin, tenant: tenant}} =
        create_tenant_and_user(email: "admin@delete-test.com")

      admin_token = access_token_for(admin)

      {:ok, %{user: member}} =
        create_tenant_and_user(tenant: tenant, email: "member@delete-test.com", role: "member")

      member_token = access_token_for(member)

      %{
        admin: admin,
        admin_token: admin_token,
        member: member,
        member_token: member_token,
        tenant: tenant
      }
    end

    test "admin can remove a user", %{conn: conn, admin_token: token, member: member} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete("/v1/tenant/users/#{member.id}")

      response = json_response(conn, 200)

      assert response["id"] == member.id
      assert response["message"] =~ "removed"

      # Verify user is suspended
      updated_member = Users.get_user!(member.id)
      assert updated_member.status == "suspended"
    end

    test "admin cannot remove self", %{conn: conn, admin_token: token, admin: admin} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete("/v1/tenant/users/#{admin.id}")

      response = json_response(conn, 403)
      assert response["message"] =~ "cannot remove yourself"
    end

    test "member cannot remove users", %{conn: conn, member_token: token, admin: admin} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete("/v1/tenant/users/#{admin.id}")

      assert json_response(conn, 403)
    end

    test "returns 404 for non-existent user", %{conn: conn, admin_token: token} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete("/v1/tenant/users/#{fake_id}")

      assert json_response(conn, 404)
    end

    test "returns 401 without authentication", %{conn: conn, member: member} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete("/v1/tenant/users/#{member.id}")

      assert json_response(conn, 401)
    end
  end

  describe "DELETE /v1/tenant/users/:id - admin removal" do
    setup do
      {:ok, %{user: admin, tenant: tenant}} =
        create_tenant_and_user(email: "admin1@admin-delete.com")

      admin_token = access_token_for(admin)

      {:ok, %{user: admin2}} =
        create_tenant_and_user(tenant: tenant, email: "admin2@admin-delete.com", role: "admin")

      %{admin: admin, admin2: admin2, admin_token: admin_token, tenant: tenant}
    end

    test "can remove an admin when multiple admins exist", %{
      conn: conn,
      admin_token: token,
      admin2: admin2
    } do
      # There are 2 admins, removing one should succeed
      result =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete("/v1/tenant/users/#{admin2.id}")
        |> json_response(200)

      assert result["id"] == admin2.id
    end

    test "cannot remove yourself even as sole admin", %{
      conn: conn,
      admin: admin,
      admin_token: admin_token,
      admin2: admin2
    } do
      # First remove admin2 so admin is the only admin
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{admin_token}")
      |> delete("/v1/tenant/users/#{admin2.id}")
      |> json_response(200)

      # Now admin is the only admin. admin tries to remove themselves.
      # This should fail with "cannot remove self"
      result =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{admin_token}")
        |> delete("/v1/tenant/users/#{admin.id}")
        |> json_response(403)

      assert result["message"] =~ "cannot remove yourself"
    end

    test "member cannot remove users", %{conn: conn, admin: admin, tenant: tenant} do
      {:ok, %{user: member}} =
        create_tenant_and_user(tenant: tenant, email: "member@admin-delete.com", role: "member")

      member_token = access_token_for(member)

      # Member tries to remove admin - should fail with forbidden
      result =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{member_token}")
        |> delete("/v1/tenant/users/#{admin.id}")
        |> json_response(403)

      assert result["message"] =~ "permission"
    end
  end
end
