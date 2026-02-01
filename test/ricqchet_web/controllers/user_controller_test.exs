defmodule RicqchetWeb.UserControllerTest do
  use RicqchetWeb.ConnCase, async: false

  alias Ricqchet.Auth
  alias Ricqchet.Auth.Token

  describe "GET /v1/users/me" do
    setup do
      # Create and verify a user
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "profileuser@example.com",
          "password" => "secure_password_123",
          "tenant_name" => "Profile Org"
        })

      {:ok, user} = Auth.verify_email(token)
      {:ok, access_token, _claims} = Token.generate_access_token(user)

      %{user: user, access_token: access_token}
    end

    test "returns user profile for authenticated user", %{
      conn: conn,
      user: user,
      access_token: token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/v1/users/me")

      response = json_response(conn, 200)

      assert response["id"] == user.id
      assert response["email"] == user.email
      assert response["role"] == user.role
      assert response["status"] == "active"
      assert response["tenant_id"] == user.tenant_id
      assert response["tenant_name"] == "Profile Org"
      assert response["confirmed_at"]
      assert response["inserted_at"]
      assert response["updated_at"]
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> get("/v1/users/me")

      assert json_response(conn, 401)
    end
  end

  describe "PATCH /v1/users/me" do
    setup do
      # Create and verify a user
      {:ok, %{user: _user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "updateuser@example.com",
          "password" => "secure_password_123",
          "tenant_name" => "Update Org"
        })

      {:ok, user} = Auth.verify_email(token)
      {:ok, access_token, _claims} = Token.generate_access_token(user)

      %{user: user, access_token: access_token}
    end

    test "returns user profile for authenticated user", %{
      conn: conn,
      user: user,
      access_token: token
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/v1/users/me", %{})

      response = json_response(conn, 200)

      assert response["id"] == user.id
      assert response["email"] == user.email
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/v1/users/me", %{})

      assert json_response(conn, 401)
    end
  end
end
