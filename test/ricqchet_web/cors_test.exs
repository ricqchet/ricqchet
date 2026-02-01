defmodule RicqchetWeb.CorsTest do
  use RicqchetWeb.ConnCase, async: true

  describe "CORS headers" do
    test "includes CORS headers for allowed origin", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "http://localhost:3000")
        |> get("/health")

      assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:3000"]
      assert get_resp_header(conn, "access-control-allow-credentials") == ["true"]
    end

    test "does not include CORS headers for disallowed origin", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "http://evil.com")
        |> get("/health")

      assert get_resp_header(conn, "access-control-allow-origin") == []
    end
  end

  describe "preflight requests" do
    test "responds to OPTIONS request with CORS headers", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "http://localhost:3000")
        |> put_req_header("access-control-request-method", "POST")
        |> put_req_header("access-control-request-headers", "content-type, authorization")
        |> options("/v1/publish")

      assert conn.status == 200
      assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:3000"]
      assert get_resp_header(conn, "access-control-allow-credentials") == ["true"]

      [allow_methods] = get_resp_header(conn, "access-control-allow-methods")
      assert String.contains?(allow_methods, "POST")

      [allow_headers] = get_resp_header(conn, "access-control-allow-headers")
      assert String.contains?(allow_headers, "content-type")
      assert String.contains?(allow_headers, "authorization")
    end

    test "includes max-age header for preflight caching", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "http://localhost:3000")
        |> put_req_header("access-control-request-method", "POST")
        |> options("/v1/publish")

      assert get_resp_header(conn, "access-control-max-age") == ["86400"]
    end

    test "rejects preflight from disallowed origin", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "http://evil.com")
        |> put_req_header("access-control-request-method", "POST")
        |> options("/v1/publish")

      assert get_resp_header(conn, "access-control-allow-origin") == []
    end
  end

  describe "CORS with authentication endpoints" do
    test "allows CORS for login endpoint", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "http://localhost:3000")
        |> put_req_header("content-type", "application/json")
        |> post(
          "/v1/auth/login",
          Jason.encode!(%{email: "test@example.com", password: "password"})
        )

      assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:3000"]
    end
  end
end
