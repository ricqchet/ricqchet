defmodule RicqchetWeb.ChannelControllerTest do
  use RicqchetWeb.ConnCase, async: false

  import Ricqchet.DataCase, only: [create_tenant_with_api_key: 0]

  alias Ricqchet.Channels.SubscriberTracker

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

    %{conn: conn, tenant: tenant, application: application, api_key: api_key}
  end

  describe "POST /v1/channels/events" do
    test "publishes to a single channel", %{conn: conn} do
      conn =
        post(conn, "/v1/channels/events", %{
          "channel" => "chat-room",
          "event" => "new-message",
          "data" => %{"text" => "Hello!"}
        })

      assert %{"event_ids" => [_id], "channel" => "chat-room"} = json_response(conn, 202)
    end

    test "publishes to multiple channels", %{conn: conn} do
      conn =
        post(conn, "/v1/channels/events", %{
          "channels" => ["room-1", "room-2", "room-3"],
          "event" => "announcement",
          "data" => %{"text" => "Hi"}
        })

      response = json_response(conn, 202)
      assert length(response["event_ids"]) == 3
    end

    test "delivers event to PubSub subscribers", %{conn: conn, application: app} do
      topic = "channels:app:#{app.id}:live-room"
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, topic)

      post(conn, "/v1/channels/events", %{
        "channel" => "live-room",
        "event" => "test-event",
        "data" => %{"key" => "value"}
      })

      assert_receive {:channel_event, payload}
      assert payload.event == "test-event"
      assert payload.data == %{"key" => "value"}
      assert payload.channel == "live-room"
    end

    test "includes socket_id in broadcast for sender exclusion", %{conn: conn, application: app} do
      topic = "channels:app:#{app.id}:exclude-room"
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, topic)

      post(conn, "/v1/channels/events", %{
        "channel" => "exclude-room",
        "event" => "test",
        "data" => %{},
        "socket_id" => "sender_123"
      })

      assert_receive {:channel_event, payload}
      assert payload.socket_id == "sender_123"
    end

    test "returns error when channel is missing", %{conn: conn} do
      conn =
        post(conn, "/v1/channels/events", %{
          "event" => "test",
          "data" => %{}
        })

      assert json_response(conn, 422)
    end

    test "returns error when event is missing", %{conn: conn} do
      conn =
        post(conn, "/v1/channels/events", %{
          "channel" => "room",
          "data" => %{}
        })

      assert json_response(conn, 422)
    end

    test "returns error for empty channels list", %{conn: conn} do
      conn =
        post(conn, "/v1/channels/events", %{
          "channels" => [],
          "event" => "test",
          "data" => %{}
        })

      assert json_response(conn, 422)
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/v1/channels/events", %{
          "channel" => "room",
          "event" => "test",
          "data" => %{}
        })

      assert json_response(conn, 401)
    end
  end

  describe "GET /v1/channels" do
    test "returns empty list when no active channels", %{conn: conn} do
      conn = get(conn, "/v1/channels")
      assert %{"channels" => []} = json_response(conn, 200)
    end

    test "returns active channels with subscriber counts", %{conn: conn, application: app} do
      SubscriberTracker.track_join(app.id, "room-a")
      SubscriberTracker.track_join(app.id, "room-a")
      SubscriberTracker.track_join(app.id, "room-b")

      conn = get(conn, "/v1/channels")
      response = json_response(conn, 200)

      channels = response["channels"]
      assert length(channels) == 2

      room_a = Enum.find(channels, &(&1["name"] == "room-a"))
      assert room_a["subscriber_count"] == 2
      assert room_a["type"] == "public"
    end
  end

  describe "GET /v1/channels/:channel_name" do
    test "returns channel info", %{conn: conn, application: app} do
      SubscriberTracker.track_join(app.id, "info-room")

      conn = get(conn, "/v1/channels/info-room")
      response = json_response(conn, 200)

      assert response["name"] == "info-room"
      assert response["subscriber_count"] == 1
      assert response["type"] == "public"
      assert response["occupied"] == true
    end

    test "returns unoccupied channel info", %{conn: conn} do
      conn = get(conn, "/v1/channels/empty-room")
      response = json_response(conn, 200)

      assert response["name"] == "empty-room"
      assert response["subscriber_count"] == 0
      assert response["occupied"] == false
    end
  end
end
