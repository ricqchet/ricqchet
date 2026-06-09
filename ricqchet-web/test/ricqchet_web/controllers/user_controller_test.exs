defmodule RicqchetWeb.UserControllerTest do
  use RicqchetWeb.ConnCase, async: false

  describe "GET /v1/users/me" do
    setup do
      {:ok, %{user: user, tenant: _tenant}} =
        create_tenant_and_user(
          email: "profileuser@example.com",
          password: "secure_password_123",
          tenant_name: "Profile Org"
        )

      access_token = access_token_for(user)

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
end
