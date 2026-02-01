defmodule RicqchetWeb.AuthControllerTest do
  use RicqchetWeb.ConnCase, async: false
  import Swoosh.TestAssertions

  alias Ricqchet.Auth
  alias Ricqchet.Auth.Token
  alias Ricqchet.Repo

  describe "POST /v1/auth/register" do
    test "creates user and tenant with valid params", %{conn: conn} do
      params = %{
        email: "newuser@example.com",
        password: "secure_password_123",
        tenant_name: "New Organization"
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/register", params)

      response = json_response(conn, 201)

      assert response["user"]["email"] == "newuser@example.com"
      assert response["user"]["role"] == "admin"
      assert response["user"]["status"] == "pending"
      assert response["user"]["id"]
      assert response["user"]["tenant_id"]
      assert response["message"] =~ "verify"
    end

    test "sends verification email", %{conn: conn} do
      params = %{
        email: "verify@example.com",
        password: "secure_password_123",
        tenant_name: "Test Org"
      }

      conn
      |> put_req_header("content-type", "application/json")
      |> post("/v1/auth/register", params)

      assert_email_sent(to: "verify@example.com", subject: "Verify your email address")
    end

    test "returns 422 with invalid email", %{conn: conn} do
      params = %{
        email: "invalid-email",
        password: "secure_password_123",
        tenant_name: "Test Org"
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/register", params)

      response = json_response(conn, 422)
      assert response["error"] == "validation_error"
      assert response["message"] =~ "email"
    end

    test "returns 422 with short password", %{conn: conn} do
      params = %{
        email: "user@example.com",
        password: "short",
        tenant_name: "Test Org"
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/register", params)

      response = json_response(conn, 422)
      assert response["error"] == "validation_error"
      assert response["message"] =~ "password"
    end

    test "returns 422 with missing tenant name", %{conn: conn} do
      params = %{
        email: "user@example.com",
        password: "secure_password_123"
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/register", params)

      response = json_response(conn, 422)
      assert response["error"] == "validation_error"
      assert response["message"] =~ "name"
    end

    test "returns 422 when email already exists", %{conn: conn} do
      # First registration
      params = %{
        email: "duplicate@example.com",
        password: "secure_password_123",
        tenant_name: "First Org"
      }

      conn
      |> put_req_header("content-type", "application/json")
      |> post("/v1/auth/register", params)

      # Second registration with same email
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/register", %{params | tenant_name: "Second Org"})

      response = json_response(conn, 422)
      assert response["error"] == "validation_error"
      assert response["message"] =~ "email"
    end
  end

  describe "POST /v1/auth/verify-email" do
    setup do
      # Create a user with pending verification
      {:ok, %{user: user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "unverified@example.com",
          "password" => "secure_password_123",
          "tenant_name" => "Test Org"
        })

      %{user: user, token: token}
    end

    test "verifies email with valid token", %{conn: conn, token: token, user: user} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/verify-email", %{token: token})

      response = json_response(conn, 200)

      assert response["message"] == "Email verified successfully"
      assert response["user"]["email"] == user.email
      assert response["user"]["status"] == "active"
      assert response["user"]["confirmed_at"]
    end

    test "returns 400 with invalid token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/verify-email", %{token: "invalid_token"})

      response = json_response(conn, 400)
      assert response["error"] == "bad_request"
      assert response["message"] =~ "Invalid"
    end

    test "returns 400 with expired token", %{conn: conn, user: user} do
      # Create an expired token
      {:ok, token} = Auth.create_email_verification_token(user)

      # Manually expire it
      token
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :hour))
      |> Repo.update!()

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/verify-email", %{token: token.token})

      response = json_response(conn, 400)
      assert response["error"] == "bad_request"
      assert response["message"] =~ "expired"
    end

    test "returns 422 when token is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/verify-email", %{})

      response = json_response(conn, 422)
      assert response["error"] == "validation_error"
    end
  end

  describe "POST /v1/auth/resend-verification" do
    setup do
      # Create a user with pending verification
      {:ok, %{user: user, verification_token: _token}} =
        Auth.register_user(%{
          "email" => "resend@example.com",
          "password" => "secure_password_123",
          "tenant_name" => "Resend Org"
        })

      # Generate a JWT for the user
      {:ok, access_token, _claims} = Token.generate_access_token(user)

      %{user: user, access_token: access_token}
    end

    test "resends verification email for unverified user", %{conn: conn, access_token: token} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/v1/auth/resend-verification")

      response = json_response(conn, 200)
      assert response["message"] =~ "Verification email"

      assert_email_sent(to: "resend@example.com", subject: "Verify your email address")
    end

    test "returns 400 for already verified user", %{conn: conn, user: user, access_token: token} do
      # Verify the user first
      {:ok, _user} = Ricqchet.Users.confirm_user(user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/v1/auth/resend-verification")

      response = json_response(conn, 400)
      assert response["error"] == "bad_request"
      assert response["message"] =~ "already verified"
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/resend-verification")

      assert json_response(conn, 401)
    end
  end

  describe "POST /v1/auth/login" do
    setup do
      # Create and verify a user
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "loginuser@example.com",
          "password" => "secure_password_123",
          "tenant_name" => "Login Org"
        })

      {:ok, verified_user} = Auth.verify_email(token)
      %{user: verified_user}
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

    test "returns 401 for unverified user", %{conn: conn} do
      # Create an unverified user
      {:ok, %{user: unverified_user}} =
        Auth.register_user(%{
          "email" => "unverified_login@example.com",
          "password" => "secure_password_123",
          "tenant_name" => "Unverified Org"
        })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/login", %{email: unverified_user.email, password: "secure_password_123"})

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
      # Create and verify a user, then login to get tokens
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "logoutuser@example.com",
          "password" => "secure_password_123",
          "tenant_name" => "Logout Org"
        })

      {:ok, _verified_user} = Auth.verify_email(token)
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
      refresh_token: refresh_token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> post("/v1/auth/logout", %{refresh_token: refresh_token, everywhere: true})

      response = json_response(conn, 200)
      assert response["message"] =~ "all sessions"
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
      # Create and verify a user, then login to get tokens
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "refreshuser@example.com",
          "password" => "secure_password_123",
          "tenant_name" => "Refresh Org"
        })

      {:ok, _verified_user} = Auth.verify_email(token)
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
      # Create and verify a user, then login to get tokens
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "changepassuser@example.com",
          "password" => "old_password_123",
          "tenant_name" => "Change Pass Org"
        })

      {:ok, _verified_user} = Auth.verify_email(token)
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
