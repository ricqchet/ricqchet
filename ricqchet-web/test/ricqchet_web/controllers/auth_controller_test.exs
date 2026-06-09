defmodule RicqchetWeb.AuthControllerTest do
  use RicqchetWeb.ConnCase, async: false
  import Swoosh.TestAssertions

  alias Ricqchet.Auth
  alias Ricqchet.Repo
  alias Ricqchet.Users

  describe "POST /v1/auth/forgot-password" do
    setup do
      {:ok, %{user: user}} = create_tenant_and_user(email: "forgotpassword@example.com")
      %{user: user}
    end

    test "sends password reset email for existing user", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/forgot-password", %{email: user.email})

      response = json_response(conn, 200)
      assert response["message"] =~ "password reset link"

      assert_email_sent(to: user.email, subject: "Reset your password")
    end

    test "returns success even for non-existent email (prevents enumeration)", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/forgot-password", %{email: "nonexistent@example.com"})

      response = json_response(conn, 200)
      # Same message regardless of whether email exists
      assert response["message"] =~ "password reset link"

      # No email should be sent
      assert_no_email_sent()
    end

    test "returns 422 when email is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/forgot-password", %{})

      response = json_response(conn, 422)
      assert response["error"] == "validation_error"
      assert response["message"] =~ "Email"
    end
  end

  describe "POST /v1/auth/reset-password" do
    setup do
      {:ok, %{user: user}} =
        create_tenant_and_user(email: "resetpassword@example.com", password: "old_password_123")

      {:ok, reset_token} = Auth.create_password_reset_token(user)

      %{user: user, reset_token: reset_token.token}
    end

    test "resets password with valid token", %{conn: conn, reset_token: token, user: user} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/reset-password", %{token: token, password: "new_password_456"})

      response = json_response(conn, 200)
      assert response["message"] =~ "Password has been reset"

      # Verify new password works
      {:ok, _auth_data} = Auth.login(user.email, "new_password_456")
    end

    test "invalidates all existing sessions after password reset", %{
      conn: conn,
      reset_token: reset_token,
      user: user
    } do
      # Create a refresh token before reset
      {:ok, refresh_token} = Auth.create_refresh_token(user)

      # Reset password
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/v1/auth/reset-password", %{token: reset_token, password: "new_password_456"})

      # Try to use the old refresh token - should fail
      conn2 =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/refresh", %{refresh_token: refresh_token.token})

      assert json_response(conn2, 401)
    end

    test "returns 400 with invalid token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/reset-password", %{token: "invalid_token", password: "new_password_123"})

      response = json_response(conn, 400)
      assert response["error"] == "bad_request"
      assert response["message"] =~ "Invalid"
    end

    test "returns 400 with expired token", %{conn: conn, user: user} do
      # Create an expired token
      {:ok, token} = Auth.create_password_reset_token(user)

      # Manually expire it
      token
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :hour))
      |> Repo.update!()

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/reset-password", %{token: token.token, password: "new_password_123"})

      response = json_response(conn, 400)
      assert response["error"] == "bad_request"
      assert response["message"] =~ "expired"
    end

    test "token can only be used once", %{conn: conn, reset_token: token} do
      # First reset should succeed
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/v1/auth/reset-password", %{token: token, password: "new_password_456"})

      # Second reset with same token should fail
      conn2 =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/reset-password", %{token: token, password: "another_password_789"})

      response = json_response(conn2, 400)
      assert response["error"] == "bad_request"
      assert response["message"] =~ "Invalid"
    end

    test "returns 422 when token or password is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/reset-password", %{})

      response = json_response(conn, 422)
      assert response["error"] == "validation_error"
    end

    test "returns 422 with invalid password (too short)", %{conn: conn, reset_token: token} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/reset-password", %{token: token, password: "short"})

      response = json_response(conn, 422)
      assert response["error"] == "validation_error"
      assert response["message"] =~ "password"
    end
  end

  describe "POST /v1/auth/login" do
    setup do
      {:ok, %{user: user, tenant: tenant}} =
        create_tenant_and_user(email: "loginuser@example.com", password: "secure_password_123")

      %{user: user, tenant: tenant}
    end

    test "returns tokens for valid credentials", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/login", %{email: user.email, password: "secure_password_123"})

      response = json_response(conn, 200)

      assert response["user"]["email"] == user.email
      assert response["user"]["status"] == "active"
      assert response["user"]["tenant_name"]
      assert response["access_token"]
      assert response["refresh_token"]
      assert response["expires_in"]
    end

    test "returns 401 for invalid password", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/login", %{email: user.email, password: "wrong_password"})

      response = json_response(conn, 401)
      assert response["error"] == "unauthorized"
      assert response["message"] =~ "Invalid"
    end

    test "returns 401 for non-existent email", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/login", %{email: "noone@example.com", password: "password123"})

      response = json_response(conn, 401)
      assert response["error"] == "unauthorized"
    end

    test "returns 401 for unconfirmed user", %{conn: conn, tenant: tenant} do
      # A user created without confirmation cannot log in until confirmed.
      {:ok, unconfirmed} =
        Users.create_user(tenant, %{
          email: "unconfirmed_login@example.com",
          password: "secure_password_123"
        })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/login", %{email: unconfirmed.email, password: "secure_password_123"})

      response = json_response(conn, 401)
      assert response["error"] == "unauthorized"
      assert response["message"] =~ "verify"
    end

    test "returns 422 when credentials are missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/login", %{})

      response = json_response(conn, 422)
      assert response["error"] == "validation_error"
    end
  end

  describe "POST /v1/auth/logout" do
    setup do
      {:ok, %{user: _user}} =
        create_tenant_and_user(email: "logoutuser@example.com", password: "secure_password_123")

      {:ok, auth_data} = Auth.login("logoutuser@example.com", "secure_password_123")

      %{
        user: auth_data.user,
        access_token: auth_data.access_token,
        refresh_token: auth_data.refresh_token
      }
    end

    test "logs out user and revokes refresh token", %{
      conn: conn,
      access_token: access_token,
      refresh_token: refresh_token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> post("/v1/auth/logout", %{refresh_token: refresh_token})

      response = json_response(conn, 200)
      assert response["message"] =~ "Logged out"

      # Try to use the refresh token - should fail
      conn2 =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/refresh", %{refresh_token: refresh_token})

      assert json_response(conn2, 401)
    end

    test "logs out everywhere when requested", %{
      conn: conn,
      access_token: access_token,
      refresh_token: refresh_token,
      user: user
    } do
      # Create a second refresh token to simulate another session
      {:ok, second_refresh_token} = Auth.create_refresh_token(user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> post("/v1/auth/logout", %{refresh_token: refresh_token, everywhere: true})

      response = json_response(conn, 200)
      assert response["message"] =~ "all sessions"

      # Verify original refresh token is invalidated
      conn2 =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/refresh", %{refresh_token: refresh_token})

      assert json_response(conn2, 401)

      # Verify second refresh token is also invalidated
      conn3 =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/refresh", %{refresh_token: second_refresh_token.token})

      assert json_response(conn3, 401)
    end

    test "returns 401 without authentication", %{conn: conn, refresh_token: refresh_token} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/logout", %{refresh_token: refresh_token})

      assert json_response(conn, 401)
    end
  end

  describe "POST /v1/auth/refresh" do
    setup do
      {:ok, %{user: _user}} =
        create_tenant_and_user(email: "refreshuser@example.com", password: "secure_password_123")

      {:ok, auth_data} = Auth.login("refreshuser@example.com", "secure_password_123")

      %{
        user: auth_data.user,
        access_token: auth_data.access_token,
        refresh_token: auth_data.refresh_token
      }
    end

    test "returns new access token with valid refresh token", %{
      conn: conn,
      refresh_token: refresh_token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/refresh", %{refresh_token: refresh_token})

      response = json_response(conn, 200)

      assert response["access_token"]
      assert response["expires_in"]
    end

    test "returns 401 with invalid refresh token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/refresh", %{refresh_token: "invalid_token"})

      response = json_response(conn, 401)
      assert response["error"] == "unauthorized"
    end

    test "returns 422 when refresh token is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/refresh", %{})

      response = json_response(conn, 422)
      assert response["error"] == "validation_error"
    end
  end

  describe "POST /v1/auth/change-password" do
    setup do
      {:ok, %{user: _user}} =
        create_tenant_and_user(email: "changepassuser@example.com", password: "old_password_123")

      {:ok, auth_data} = Auth.login("changepassuser@example.com", "old_password_123")

      %{
        user: auth_data.user,
        access_token: auth_data.access_token,
        refresh_token: auth_data.refresh_token
      }
    end

    test "changes password and returns new tokens", %{conn: conn, access_token: token} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/v1/auth/change-password", %{
          current_password: "old_password_123",
          new_password: "new_password_456"
        })

      response = json_response(conn, 200)

      assert response["access_token"]
      assert response["refresh_token"]
      assert response["expires_in"]
      assert response["user"]["email"] == "changepassuser@example.com"

      # Verify new password works
      {:ok, _auth_data} = Auth.login("changepassuser@example.com", "new_password_456")
    end

    test "invalidates old access token after password change", %{
      conn: conn,
      access_token: old_token
    } do
      # Change password
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{old_token}")
      |> post("/v1/auth/change-password", %{
        current_password: "old_password_123",
        new_password: "new_password_456"
      })

      # Try to use old token - should fail
      conn2 =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{old_token}")
        |> get("/v1/users/me")

      assert json_response(conn2, 401)
    end

    test "returns 401 with incorrect current password", %{conn: conn, access_token: token} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/v1/auth/change-password", %{
          current_password: "wrong_password",
          new_password: "new_password_456"
        })

      response = json_response(conn, 401)
      assert response["error"] == "unauthorized"
      assert response["message"] =~ "incorrect"
    end

    test "returns 422 when passwords are missing", %{conn: conn, access_token: token} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/v1/auth/change-password", %{})

      response = json_response(conn, 422)
      assert response["error"] == "validation_error"
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/change-password", %{
          current_password: "old_password",
          new_password: "new_password_123"
        })

      assert json_response(conn, 401)
    end
  end
end
