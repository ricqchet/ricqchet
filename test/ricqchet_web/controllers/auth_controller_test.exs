defmodule RicqchetWeb.AuthControllerTest do
  use RicqchetWeb.ConnCase, async: false
  import Swoosh.TestAssertions

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
end
