defmodule RicqchetWeb.Plugs.AuthRateLimiterTest do
  use RicqchetWeb.ConnCase, async: false

  alias RicqchetWeb.Plugs.AuthRateLimiter

  setup do
    # Reset the rate limiter before each test
    AuthRateLimiter.reset()
    :ok
  end

  describe "rate limiting" do
    test "allows requests under the limit", %{conn: conn} do
      # Default is 5 requests per minute
      for _ <- 1..5 do
        conn =
          conn
          |> put_req_header("content-type", "application/json")
          |> post("/v1/auth/forgot-password", %{email: "test@example.com"})

        assert conn.status == 200
      end
    end

    test "blocks requests over the limit", %{conn: conn} do
      # Make 5 requests (the limit)
      for _ <- 1..5 do
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/forgot-password", %{email: "test@example.com"})
      end

      # The 6th request should be rate limited
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/auth/forgot-password", %{email: "test@example.com"})

      response = json_response(conn, 429)
      assert response["error"] == "rate_limit_exceeded"
      assert get_resp_header(conn, "retry-after") == ["60"]
    end
  end
end
