defmodule RicqchetWeb.TenantControllerTest do
  use RicqchetWeb.ConnCase, async: false

  alias Ricqchet.Auth
  alias Ricqchet.Auth.Token
  alias Ricqchet.Repo
  alias Ricqchet.Users

  describe "GET /v1/tenant" do
    setup do
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "admin@tenant-test.com",
          "password" => "secure_password_123",
          "tenant_name" => "Tenant Test Org"
        })

      {:ok, unloaded_admin} = Auth.verify_email(token)
      admin = Repo.preload(unloaded_admin, :tenant)
      {:ok, admin_token, _claims} = Token.generate_access_token(admin)

      # Create a member user
      {:ok, unconfirmed_member} =
        Users.create_user(admin.tenant, %{
          "email" => "member@tenant-test.com",
          "password" => "secure_password_123",
          "role" => "member"
        })

      {:ok, member} = Users.confirm_user(unconfirmed_member)
      {:ok, member_token, _claims} = Token.generate_access_token(member)

      %{
        admin: admin,
        admin_token: admin_token,
        member: member,
        member_token: member_token,
        tenant: admin.tenant
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
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "admin@patch-test.com",
          "password" => "secure_password_123",
          "tenant_name" => "Patch Test Org"
        })

      {:ok, unloaded_admin} = Auth.verify_email(token)
      admin = Repo.preload(unloaded_admin, :tenant)
      {:ok, admin_token, _claims} = Token.generate_access_token(admin)

      # Create a member user
      {:ok, unconfirmed_member} =
        Users.create_user(admin.tenant, %{
          "email" => "member@patch-test.com",
          "password" => "secure_password_123",
          "role" => "member"
        })

      {:ok, member} = Users.confirm_user(unconfirmed_member)
      {:ok, member_token, _claims} = Token.generate_access_token(member)

      %{
        admin: admin,
        admin_token: admin_token,
        member: member,
        member_token: member_token,
        tenant: admin.tenant
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

      assert json_response(conn, 403)
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
