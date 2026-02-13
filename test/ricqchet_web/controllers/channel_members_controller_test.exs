defmodule RicqchetWeb.ChannelMembersControllerTest do
  use RicqchetWeb.ConnCase, async: false

  import Ricqchet.DataCase, only: [create_tenant_with_api_key: 0]

  alias RicqchetWeb.Channels.Presence

  setup %{conn: conn} do
    {:ok, %{tenant: _tenant, application: app, api_key: api_key}} =
      create_tenant_with_api_key()

    {:ok, application} =
      app
      |> Ecto.Changeset.change(channels_enabled: true)
      |> Ricqchet.Repo.update()

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{api_key.api_key}")
      |> put_req_header("content-type", "application/json")

    %{conn: conn, application: application, api_key: api_key}
  end

  describe "GET /v1/channels/:channel_name/members" do
    test "returns empty list when no members connected", %{conn: conn} do
      conn = get(conn, "/v1/channels/presence-lobby/members")
      response = json_response(conn, 200)
      assert response["members"] == []
    end

    test "returns connected members", %{conn: conn, application: app} do
      topic = "channels:app:#{app.id}:presence-api-room"

      Presence.track(
        self(),
        topic,
        "user_1",
        %{user_info: %{"name" => "Alice"}, joined_at: 1_000_000}
      )

      conn = get(conn, "/v1/channels/presence-api-room/members")
      response = json_response(conn, 200)

      assert length(response["members"]) == 1
      member = hd(response["members"])
      assert member["user_id"] == "user_1"
      assert member["user_info"] == %{"name" => "Alice"}
      assert member["joined_at"] == 1_000_000
    end

    test "rejects non-presence channels", %{conn: conn} do
      conn = get(conn, "/v1/channels/chat-room/members")
      assert json_response(conn, 422)
    end

    test "rejects private channels", %{conn: conn} do
      conn = get(conn, "/v1/channels/private-room/members")
      assert json_response(conn, 422)
    end

    test "rejects invalid channel name", %{conn: conn} do
      conn = get(conn, "/v1/channels/invalid%20name!/members")
      assert json_response(conn, 422)
    end

    test "returns 403 when channels not enabled", %{conn: conn, application: app} do
      app
      |> Ecto.Changeset.change(channels_enabled: false)
      |> Ricqchet.Repo.update!()

      conn = get(conn, "/v1/channels/presence-lobby/members")
      assert json_response(conn, 403)
    end
  end
end
