defmodule RicqchetWeb.TenantUserControllerTest do
  use RicqchetWeb.ConnCase, async: false

  alias Ricqchet.Auth
  alias Ricqchet.Auth.Token
  alias Ricqchet.Repo
  alias Ricqchet.Tenants
  alias Ricqchet.Users

  describe "GET /v1/tenant/users" do
    setup do
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "admin@users-test.com",
          "password" => "secure_password_123",
          "tenant_name" => "Users Test Org"
        })

      {:ok, unloaded_admin} = Auth.verify_email(token)
      admin = Repo.preload(unloaded_admin, :tenant)
      {:ok, admin_token, _claims} = Token.generate_access_token(admin)

      # Create additional users
      {:ok, unconfirmed_member} =
        Users.create_user(admin.tenant, %{
          "email" => "member@users-test.com",
          "password" => "secure_password_123",
          "role" => "member"
        })

      {:ok, _member} = Users.confirm_user(unconfirmed_member)

      {:ok, unconfirmed_viewer} =
        Users.create_user(admin.tenant, %{
          "email" => "viewer@users-test.com",
          "password" => "secure_password_123",
          "role" => "viewer"
        })

      {:ok, _viewer} = Users.confirm_user(unconfirmed_viewer)

      %{
        admin: admin,
        admin_token: admin_token,
        tenant: admin.tenant
      }
    end

    test "lists all users in tenant", %{
      conn: conn,
      admin_token: token
    } do
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

    test "supports pagination", %{
      conn: conn,
      admin_token: token
    } do
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

  describe "POST /v1/tenant/users/invite" do
    setup do
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "admin@invite-test.com",
          "password" => "secure_password_123",
          "tenant_name" => "Invite Test Org"
        })

      {:ok, unloaded_admin} = Auth.verify_email(token)
      admin = Repo.preload(unloaded_admin, :tenant)
      {:ok, admin_token, _claims} = Token.generate_access_token(admin)

      # Create a member user
      {:ok, unconfirmed_member} =
        Users.create_user(admin.tenant, %{
          "email" => "member@invite-test.com",
          "password" => "secure_password_123",
          "role" => "member"
        })

      {:ok, member} = Users.confirm_user(unconfirmed_member)
      {:ok, member_token, _claims} = Token.generate_access_token(member)

      %{
        admin: admin,
        admin_token: admin_token,
        member_token: member_token,
        tenant: admin.tenant
      }
    end

    test "admin can invite a new user", %{
      conn: conn,
      admin_token: token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/v1/tenant/users/invite", %{
          "email" => "newuser@example.com",
          "role" => "member"
        })

      response = json_response(conn, 201)

      assert response["email"] == "newuser@example.com"
      assert response["role"] == "member"
      assert response["status"] == "pending"
      assert response["expires_at"]
    end

    test "member cannot invite users", %{
      conn: conn,
      member_token: token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/v1/tenant/users/invite", %{
          "email" => "newuser@example.com",
          "role" => "member"
        })

      assert json_response(conn, 403)
    end

    test "cannot invite with duplicate email in same tenant", %{
      conn: conn,
      admin_token: token
    } do
      # First invitation
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/v1/tenant/users/invite", %{
        "email" => "duplicate@example.com",
        "role" => "member"
      })

      # Second invitation with same email
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/v1/tenant/users/invite", %{
          "email" => "duplicate@example.com",
          "role" => "member"
        })

      assert json_response(conn, 422)
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/tenant/users/invite", %{
          "email" => "newuser@example.com",
          "role" => "member"
        })

      assert json_response(conn, 401)
    end
  end

  describe "PATCH /v1/tenant/users/:id" do
    setup do
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "admin@role-test.com",
          "password" => "secure_password_123",
          "tenant_name" => "Role Test Org"
        })

      {:ok, unloaded_admin} = Auth.verify_email(token)
      admin = Repo.preload(unloaded_admin, :tenant)
      {:ok, admin_token, _claims} = Token.generate_access_token(admin)

      # Create another admin
      {:ok, unconfirmed_admin2} =
        Users.create_user(admin.tenant, %{
          "email" => "admin2@role-test.com",
          "password" => "secure_password_123",
          "role" => "admin"
        })

      {:ok, admin2} = Users.confirm_user(unconfirmed_admin2)

      # Create a member user
      {:ok, unconfirmed_member} =
        Users.create_user(admin.tenant, %{
          "email" => "member@role-test.com",
          "password" => "secure_password_123",
          "role" => "member"
        })

      {:ok, member} = Users.confirm_user(unconfirmed_member)
      {:ok, member_token, _claims} = Token.generate_access_token(member)

      %{
        admin: admin,
        admin2: admin2,
        admin_token: admin_token,
        member: member,
        member_token: member_token,
        tenant: admin.tenant
      }
    end

    test "admin can update user role", %{
      conn: conn,
      admin_token: token,
      member: member
    } do
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

    test "member cannot update roles", %{
      conn: conn,
      member_token: token,
      admin: admin
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/v1/tenant/users/#{admin.id}", %{"role" => "viewer"})

      assert json_response(conn, 403)
    end

    test "returns 404 for non-existent user", %{
      conn: conn,
      admin_token: token
    } do
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
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "only-admin@test.com",
          "password" => "secure_password_123",
          "tenant_name" => "Single Admin Org"
        })

      {:ok, unloaded_admin} = Auth.verify_email(token)
      admin = Repo.preload(unloaded_admin, :tenant)
      {:ok, admin_token, _claims} = Token.generate_access_token(admin)

      %{
        admin: admin,
        admin_token: admin_token,
        tenant: admin.tenant
      }
    end

    test "cannot demote last admin", %{
      conn: conn,
      admin_token: token,
      admin: admin
    } do
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
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "admin@delete-test.com",
          "password" => "secure_password_123",
          "tenant_name" => "Delete Test Org"
        })

      {:ok, unloaded_admin} = Auth.verify_email(token)
      admin = Repo.preload(unloaded_admin, :tenant)
      {:ok, admin_token, _claims} = Token.generate_access_token(admin)

      # Create a member user
      {:ok, unconfirmed_member} =
        Users.create_user(admin.tenant, %{
          "email" => "member@delete-test.com",
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

    test "admin can remove a user", %{
      conn: conn,
      admin_token: token,
      member: member
    } do
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

    test "admin cannot remove self", %{
      conn: conn,
      admin_token: token,
      admin: admin
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete("/v1/tenant/users/#{admin.id}")

      response = json_response(conn, 403)
      assert response["message"] =~ "cannot remove yourself"
    end

    test "member cannot remove users", %{
      conn: conn,
      member_token: token,
      admin: admin
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete("/v1/tenant/users/#{admin.id}")

      assert json_response(conn, 403)
    end

    test "returns 404 for non-existent user", %{
      conn: conn,
      admin_token: token
    } do
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

  describe "POST /v1/auth/accept-invite" do
    setup do
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "admin@accept-test.com",
          "password" => "secure_password_123",
          "tenant_name" => "Accept Test Org"
        })

      {:ok, unloaded_admin} = Auth.verify_email(token)
      admin = Repo.preload(unloaded_admin, :tenant)

      # Create an invitation
      {:ok, invitation} =
        Tenants.invite_user(admin.tenant, admin, %{
          "email" => "invitee@example.com",
          "role" => "member"
        })

      %{
        admin: admin,
        tenant: admin.tenant,
        invitation: invitation
      }
    end

    test "accepts invitation and creates user", %{
      conn: conn,
      tenant: tenant,
      invitation: invitation
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/accept-invite", %{
          "token" => invitation.token,
          "password" => "new_secure_password_123"
        })

      response = json_response(conn, 200)

      assert response["user"]["email"] == "invitee@example.com"
      assert response["user"]["role"] == "member"
      assert response["user"]["status"] == "active"
      assert response["user"]["tenant_id"] == tenant.id
      assert response["access_token"]
      assert response["refresh_token"]
      assert response["expires_in"]
    end

    test "returns error for invalid token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/accept-invite", %{
          "token" => "invalid_token",
          "password" => "new_secure_password_123"
        })

      response = json_response(conn, 400)
      assert response["error"] == "invalid_token"
    end

    test "returns error for already used invitation", %{
      conn: conn,
      invitation: invitation
    } do
      # Accept invitation first time
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/v1/auth/accept-invite", %{
        "token" => invitation.token,
        "password" => "new_secure_password_123"
      })

      # Try to accept again
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/accept-invite", %{
          "token" => invitation.token,
          "password" => "another_password_123"
        })

      response = json_response(conn, 400)
      assert response["error"] == "invitation_not_pending"
    end

    test "returns error for weak password", %{
      conn: conn,
      invitation: invitation
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/accept-invite", %{
          "token" => invitation.token,
          "password" => "short"
        })

      assert json_response(conn, 422)
    end

    test "returns error for expired invitation", %{
      conn: conn,
      admin: admin,
      tenant: tenant
    } do
      # Create an invitation that expires immediately
      {:ok, invitation} =
        Tenants.invite_user(tenant, admin, %{
          email: "expired@example.com",
          role: "member",
          ttl: 0
        })

      # Small delay to ensure expiration
      Process.sleep(10)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/accept-invite", %{
          "token" => invitation.token,
          "password" => "new_secure_password_123"
        })

      response = json_response(conn, 400)
      assert response["error"] == "token_expired"
    end

    test "returns error when user already exists in tenant", %{
      conn: conn,
      admin: admin,
      tenant: tenant
    } do
      # Create an invitation for the admin's email (who already exists)
      {:ok, invitation} =
        Tenants.invite_user(tenant, admin, %{
          "email" => admin.email,
          "role" => "member"
        })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/accept-invite", %{
          "token" => invitation.token,
          "password" => "new_secure_password_123"
        })

      response = json_response(conn, 409)
      assert response["error"] == "user_already_exists"
    end
  end

  describe "DELETE /v1/tenant/users/:id - admin removal" do
    setup do
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "admin1@admin-delete.com",
          "password" => "secure_password_123",
          "tenant_name" => "Admin Delete Org"
        })

      {:ok, unloaded_admin} = Auth.verify_email(token)
      admin = Repo.preload(unloaded_admin, :tenant)
      {:ok, admin_token, _claims} = Token.generate_access_token(admin)

      # Create another admin
      {:ok, unconfirmed_admin2} =
        Users.create_user(admin.tenant, %{
          "email" => "admin2@admin-delete.com",
          "password" => "secure_password_123",
          "role" => "admin"
        })

      {:ok, admin2} = Users.confirm_user(unconfirmed_admin2)

      %{
        admin: admin,
        admin2: admin2,
        admin_token: admin_token,
        tenant: admin.tenant
      }
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

    test "member cannot remove users", %{
      conn: conn,
      admin: admin,
      tenant: tenant
    } do
      # Create a member
      {:ok, unconfirmed_member} =
        Users.create_user(tenant, %{
          "email" => "member@admin-delete.com",
          "password" => "secure_password_123",
          "role" => "member"
        })

      {:ok, member} = Users.confirm_user(unconfirmed_member)
      {:ok, member_token, _claims} = Token.generate_access_token(member)

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
