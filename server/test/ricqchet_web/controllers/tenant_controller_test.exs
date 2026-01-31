defmodule RicqchetWeb.TenantControllerTest do
  use RicqchetWeb.ConnCase, async: false

  import Ricqchet.DataCase, only: [create_tenant_with_api_key: 0]

  setup %{conn: conn} do
    {:ok, %{tenant: tenant, api_key: api_key}} = create_tenant_with_api_key()

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{api_key.api_key}")
      |> put_req_header("content-type", "application/json")

    %{conn: conn, tenant: tenant, api_key: api_key}
  end

  describe "signing_secret/2" do
    test "returns the signing secret as base64", %{conn: conn, tenant: tenant} do
      conn = get(conn, "/v1/signing-secret")

      response = json_response(conn, 200)
      assert response["signing_secret"]

      # Verify it decodes to the correct bytes
      decoded = Base.decode64!(response["signing_secret"])
      assert decoded == tenant.signing_secret
    end

    test "signing secret is 32 bytes", %{conn: conn} do
      conn = get(conn, "/v1/signing-secret")

      response = json_response(conn, 200)
      decoded = Base.decode64!(response["signing_secret"])

      assert byte_size(decoded) == 32
    end

    test "returns 401 without auth header", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> get("/v1/signing-secret")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end
end
