defmodule RicqchetWeb.ChannelEventControllerTest do
  use RicqchetWeb.ConnCase, async: false

  import Ricqchet.DataCase, only: [create_tenant_with_api_key: 0]

  alias Ricqchet.Channels.ChannelEvent
  alias Ricqchet.Repo

  setup %{conn: conn} do
    {:ok, %{tenant: tenant, application: app, api_key: api_key}} =
      create_tenant_with_api_key()

    {:ok, application} =
      app
      |> Ecto.Changeset.change(channels_enabled: true)
      |> Ricqchet.Repo.update()

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{api_key.api_key}")
      |> put_req_header("content-type", "application/json")

    %{conn: conn, tenant: tenant, application: application}
  end

  defp insert_event(app_id, tenant_id, channel, event_name, data \\ %{}) do
    %ChannelEvent{application_id: app_id, tenant_id: tenant_id}
    |> ChannelEvent.changeset(%{
      channel: channel,
      event_name: event_name,
      data: Jason.encode!(data),
      data_size_bytes: byte_size(Jason.encode!(data))
    })
    |> Repo.insert!()
  end

  describe "GET /v1/channels/:channel_name/events" do
    test "returns recent events", %{conn: conn, application: app, tenant: tenant} do
      insert_event(app.id, tenant.id, "chat", "msg-1", %{text: "hello"})
      insert_event(app.id, tenant.id, "chat", "msg-2", %{text: "world"})

      conn = get(conn, "/v1/channels/chat/events")
      response = json_response(conn, 200)

      assert length(response["events"]) == 2
      [first, second] = response["events"]
      assert first["event"] == "msg-1"
      assert second["event"] == "msg-2"
      assert first["data"] == %{"text" => "hello"}
      assert is_integer(first["sequence"])
      assert first["id"] != nil
    end

    test "returns events since a given event id", %{
      conn: conn,
      application: app,
      tenant: tenant
    } do
      e1 = insert_event(app.id, tenant.id, "chat", "msg-1")
      insert_event(app.id, tenant.id, "chat", "msg-2")
      insert_event(app.id, tenant.id, "chat", "msg-3")

      conn = get(conn, "/v1/channels/chat/events?since_id=#{e1.id}")
      response = json_response(conn, 200)

      assert length(response["events"]) == 2
      event_names = Enum.map(response["events"], & &1["event"])
      assert event_names == ["msg-2", "msg-3"]
    end

    test "returns 422 when since_id event not found", %{conn: conn} do
      fake_id = Ecto.UUID.generate()
      conn = get(conn, "/v1/channels/chat/events?since_id=#{fake_id}")
      assert json_response(conn, 422)
    end

    test "respects limit parameter", %{conn: conn, application: app, tenant: tenant} do
      for i <- 1..5 do
        insert_event(app.id, tenant.id, "chat", "msg-#{i}")
      end

      conn = get(conn, "/v1/channels/chat/events?limit=2")
      response = json_response(conn, 200)
      assert length(response["events"]) == 2
    end

    test "returns empty list for channel with no events", %{conn: conn} do
      conn = get(conn, "/v1/channels/chat/events")
      response = json_response(conn, 200)
      assert response["events"] == []
    end

    test "rejects invalid channel name", %{conn: conn} do
      conn = get(conn, "/v1/channels/invalid%20name!/events")
      assert json_response(conn, 422)
    end

    test "returns 403 when channels not enabled", %{conn: conn, application: app} do
      app
      |> Ecto.Changeset.change(channels_enabled: false)
      |> Ricqchet.Repo.update!()

      conn = get(conn, "/v1/channels/chat/events")
      assert json_response(conn, 403)
    end
  end
end
