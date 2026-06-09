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
      assert response["channels"] == ["room-1", "room-2", "room-3"]
      refute Map.has_key?(response, "channel")
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

    test "rejects invalid channel name", %{conn: conn} do
      conn =
        post(conn, "/v1/channels/events", %{
          "channel" => "invalid name!",
          "event" => "test",
          "data" => %{}
        })

      assert json_response(conn, 422)
    end

    test "accepts private channel prefix", %{conn: conn} do
      conn =
        post(conn, "/v1/channels/events", %{
          "channel" => "private-room",
          "event" => "test",
          "data" => %{}
        })

      assert json_response(conn, 202)
    end

    test "returns 403 when channels not enabled", %{conn: conn, application: app} do
      app
      |> Ecto.Changeset.change(channels_enabled: false)
      |> Ricqchet.Repo.update!()

      conn =
        post(conn, "/v1/channels/events", %{
          "channel" => "room",
          "event" => "test",
          "data" => %{}
        })

      assert json_response(conn, 403)
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

  describe "POST /v1/channels/events/batch" do
    test "publishes batch of events to different channels", %{conn: conn} do
      conn =
        post(conn, "/v1/channels/events/batch", %{
          "batch" => [
            %{"channel" => "chat-1", "event" => "msg", "data" => %{"text" => "hi"}},
            %{"channel" => "chat-2", "event" => "msg", "data" => %{"text" => "hello"}}
          ]
        })

      response = json_response(conn, 202)
      results = response["results"]
      assert length(results) == 2
      assert Enum.all?(results, &(&1["status"] == "ok"))
      assert Enum.all?(results, &is_binary(&1["event_id"]))
      assert Enum.map(results, & &1["channel"]) == ["chat-1", "chat-2"]
    end

    test "supports socket_id per event", %{conn: conn, application: app} do
      topic = "channels:app:#{app.id}:batch-room"
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, topic)

      post(conn, "/v1/channels/events/batch", %{
        "batch" => [
          %{
            "channel" => "batch-room",
            "event" => "test",
            "data" => %{},
            "socket_id" => "sender_456"
          }
        ]
      })

      assert_receive {:channel_event, payload}
      assert payload.socket_id == "sender_456"
    end

    test "returns error for empty batch", %{conn: conn} do
      conn =
        post(conn, "/v1/channels/events/batch", %{
          "batch" => []
        })

      assert json_response(conn, 422)
    end

    test "returns error when batch exceeds max size", %{conn: conn} do
      events =
        Enum.map(1..11, fn i ->
          %{"channel" => "room-#{i}", "event" => "msg", "data" => %{}}
        end)

      conn = post(conn, "/v1/channels/events/batch", %{"batch" => events})
      assert json_response(conn, 422)
    end

    test "returns error when batch param is missing", %{conn: conn} do
      conn = post(conn, "/v1/channels/events/batch", %{"events" => []})
      assert json_response(conn, 422)
    end

    test "handles partial failure with invalid channel", %{conn: conn} do
      conn =
        post(conn, "/v1/channels/events/batch", %{
          "batch" => [
            %{"channel" => "valid-channel", "event" => "msg", "data" => %{}},
            %{"channel" => "invalid name!", "event" => "msg", "data" => %{}}
          ]
        })

      response = json_response(conn, 202)
      results = response["results"]
      assert length(results) == 2

      [ok_result, error_result] = results
      assert ok_result["status"] == "ok"
      assert ok_result["event_id"] != nil
      assert error_result["status"] == "error"
      assert error_result["error"] != nil
    end

    test "handles missing required fields per event", %{conn: conn} do
      conn =
        post(conn, "/v1/channels/events/batch", %{
          "batch" => [
            %{"channel" => "room", "data" => %{}},
            %{"event" => "msg", "data" => %{}}
          ]
        })

      response = json_response(conn, 202)
      results = response["results"]
      assert length(results) == 2
      assert Enum.all?(results, &(&1["status"] == "error"))
    end

    test "returns 403 when channels not enabled", %{conn: conn, application: app} do
      app
      |> Ecto.Changeset.change(channels_enabled: false)
      |> Ricqchet.Repo.update!()

      conn =
        post(conn, "/v1/channels/events/batch", %{
          "batch" => [
            %{"channel" => "room", "event" => "test", "data" => %{}}
          ]
        })

      assert json_response(conn, 403)
    end
  end
end
