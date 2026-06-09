defmodule RicqchetWeb.Plugs.RequireScopeTest do
  @moduledoc """
  Integration coverage for the `:authenticated` REST pipeline scope gate.

  A browser-safe `subscribe` key must be rejected with 403 on every
  key-authenticated REST relay endpoint — most importantly the webhook signing
  secret, whose exposure would let a holder forge webhook signatures. A full
  `relay` key (and any pre-scope key, which backfills to `relay`) must pass.
  """
  use RicqchetWeb.ConnCase, async: false

  import Ricqchet.DataCase, only: [create_tenant_with_api_key: 3]

  # Representative endpoints across the whole key-authed relay surface.
  @relay_endpoints [
    {:post, "/v1/publish", ~s({"event":"x"})},
    {:get, "/v1/signing-secret", nil},
    {:post, "/v1/channels/events", ~s({"channel":"c","event":"e","data":{}})},
    {:post, "/v1/channels/events/batch", ~s({"events":[]})},
    {:get, "/v1/channels", nil},
    {:get, "/v1/channels/room", nil},
    {:get, "/v1/channels/room/events", nil},
    {:get, "/v1/channels/room/members", nil},
    {:get, "/v1/messages/#{Ecto.UUID.generate()}", nil},
    {:delete, "/v1/messages/#{Ecto.UUID.generate()}", nil},
    {:delete, "/v1/channels/users/u1/connections", nil}
  ]

  defp request(conn, :get, path, _body), do: get(conn, path)
  defp request(conn, :post, path, body), do: post(conn, path, body)
  defp request(conn, :delete, path, _body), do: delete(conn, path)

  defp auth_conn(conn, api_key) do
    conn
    |> put_req_header("authorization", "Bearer #{api_key.api_key}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("ricqchet-destination", "https://example.com/api")
  end

  describe "subscribe-scoped key on REST relay endpoints" do
    setup %{conn: conn} do
      {:ok, %{api_key: api_key}} =
        create_tenant_with_api_key(%{}, %{channels_enabled: true}, %{scope: "subscribe"})

      %{conn: auth_conn(conn, api_key)}
    end

    test "is rejected with 403 forbidden on every relay endpoint", %{conn: base_conn} do
      for {method, path, body} <- @relay_endpoints do
        conn = request(base_conn, method, path, body)

        assert conn.status == 403,
               "expected 403 for #{method} #{path}, got #{conn.status}"

        assert json_response(conn, 403)["error"] == "forbidden"
      end
    end
  end

  describe "relay-scoped key on REST relay endpoints" do
    setup %{conn: conn} do
      {:ok, %{api_key: api_key}} =
        create_tenant_with_api_key(%{}, %{channels_enabled: true}, %{scope: "relay"})

      %{conn: auth_conn(conn, api_key)}
    end

    test "passes the scope gate (never 403 forbidden)", %{conn: base_conn} do
      for {method, path, body} <- @relay_endpoints do
        conn = request(base_conn, method, path, body)

        refute conn.status == 403,
               "relay key was forbidden on #{method} #{path} (status #{conn.status})"
      end
    end

    test "can read the signing secret", %{conn: base_conn} do
      conn = get(base_conn, "/v1/signing-secret")
      assert json_response(conn, 200)["signing_secret"]
    end
  end
end
