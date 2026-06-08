defmodule RicqchetWeb.Channels.PubsubChannelTest do
  use RicqchetWeb.ChannelCase, async: false

  import Ricqchet.DataCase, only: [create_tenant_with_api_key: 0]

  alias Ricqchet.Channels.ChannelEvent
  alias Ricqchet.Channels.ConnectionTracker
  alias Ricqchet.Channels.NamespaceCache
  alias Ricqchet.Channels.Namespaces
  alias Ricqchet.Channels.SubscriberTracker
  alias RicqchetWeb.Channels.ChannelSocket

  setup do
    NamespaceCache.invalidate_all()

    {:ok, %{tenant: tenant, application: app, api_key: api_key}} =
      create_tenant_with_api_key()

    {:ok, application} =
      app
      |> Ecto.Changeset.change(channels_enabled: true)
      |> Ricqchet.Repo.update()

    {:ok, socket} =
      connect(ChannelSocket, %{
        "api_key" => api_key.api_key,
        "user_id" => "user_123"
      })

    %{socket: socket, application: application, tenant: tenant, api_key: api_key}
  end

  defp reconnect_socket(api_key) do
    {:ok, socket} =
      connect(ChannelSocket, %{
        "api_key" => api_key.api_key,
        "user_id" => "user_123"
      })

    socket
  end

  # Internal, application-scoped PubSub topic that server-published events and
  # presence are namespaced on. Clients join with the bare channel name; the
  # server routes through this topic for tenant isolation.
  defp internal_topic(app_id, channel_name), do: "channels:app:#{app_id}:#{channel_name}"

  describe "join/3 - public channels" do
    test "joins a public channel", %{socket: socket} do
      assert {:ok, _reply, _socket} = subscribe_and_join(socket, "chat-room", %{})
    end

    test "tracks subscriber count on join", %{socket: socket, application: app} do
      {:ok, _reply, _socket} = subscribe_and_join(socket, "tracked-room", %{})
      assert SubscriberTracker.get_count(app.id, "tracked-room") == 1
    end

    test "isolates same-named channels across applications", %{socket: socket, application: app} do
      {:ok, _reply, _socket} = subscribe_and_join(socket, "chat-room", %{})

      other_app_id = Ecto.UUID.generate()

      foreign_payload = %{
        id: Ecto.UUID.generate(),
        event: "new-message",
        data: %{"text" => "from other app"},
        channel: "chat-room",
        socket_id: nil
      }

      # An event for a different application's identically-named channel must not
      # reach this subscriber — isolation now comes from the API key, not the topic.
      Phoenix.PubSub.broadcast(
        Ricqchet.PubSub,
        internal_topic(other_app_id, "chat-room"),
        {:channel_event, foreign_payload}
      )

      refute_push "new-message", _, 200

      Phoenix.PubSub.broadcast(
        Ricqchet.PubSub,
        internal_topic(app.id, "chat-room"),
        {:channel_event, %{foreign_payload | data: %{"text" => "from own app"}}}
      )

      assert_push "new-message", %{data: %{"text" => "from own app"}}
    end

    test "accepts hierarchical (dotted) channel names", %{socket: socket} do
      assert {:ok, _reply, _socket} = subscribe_and_join(socket, "orders.us.west", %{})
    end

    test "rejects invalid channel name", %{socket: socket} do
      assert {:error, %{reason: "invalid channel name" <> _}} =
               subscribe_and_join(socket, "invalid name!", %{})
    end

    test "rejects channel name that is too long", %{socket: socket} do
      long_name = String.duplicate("a", 165)

      assert {:error, %{reason: "invalid channel name" <> _}} =
               subscribe_and_join(socket, long_name, %{})
    end

    test "accepts maximum length channel name", %{socket: socket} do
      name = String.duplicate("a", 164)
      assert {:ok, _reply, _socket} = subscribe_and_join(socket, name, %{})
    end

    test "rejects channel name containing reserved characters", %{socket: socket} do
      assert {:error, %{reason: "invalid channel name" <> _}} =
               subscribe_and_join(socket, "channels:bad", %{})
    end
  end

  describe "join/3 - private channels" do
    test "joins private channel with auth endpoint approval", %{
      application: app,
      api_key: api_key
    } do
      bypass = Bypass.open()

      app
      |> Ecto.Changeset.change(channels_auth_endpoint: "http://localhost:#{bypass.port}/auth")
      |> Ricqchet.Repo.update!()

      socket = reconnect_socket(api_key)

      Bypass.expect_once(bypass, "POST", "/auth", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{ok: true}))
      end)

      assert {:ok, _reply, _socket} = subscribe_and_join(socket, "private-room", %{})
    end

    test "rejects private channel when auth returns 403", %{
      application: app,
      api_key: api_key
    } do
      bypass = Bypass.open()

      app
      |> Ecto.Changeset.change(channels_auth_endpoint: "http://localhost:#{bypass.port}/auth")
      |> Ricqchet.Repo.update!()

      socket = reconnect_socket(api_key)

      Bypass.expect_once(bypass, "POST", "/auth", fn conn ->
        Plug.Conn.resp(conn, 403, "Forbidden")
      end)

      assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, "private-room", %{})
    end

    test "rejects private channel when no auth endpoint configured", %{socket: socket} do
      assert {:error, %{reason: "auth_endpoint_not_configured"}} =
               subscribe_and_join(socket, "private-room", %{})
    end

    test "rejects private channel when auth endpoint is down", %{
      application: app,
      api_key: api_key
    } do
      bypass = Bypass.open()

      app
      |> Ecto.Changeset.change(channels_auth_endpoint: "http://localhost:#{bypass.port}/auth")
      |> Ricqchet.Repo.update!()

      socket = reconnect_socket(api_key)
      Bypass.down(bypass)

      assert {:error, %{reason: "auth_unavailable"}} =
               subscribe_and_join(socket, "private-room", %{})
    end

    test "uses namespace auth endpoint over app-level", %{
      application: app,
      tenant: tenant,
      api_key: api_key
    } do
      ns_bypass = Bypass.open()

      Namespaces.create_namespace(
        %{
          pattern: "private-vip-*",
          priority: 10,
          auth_endpoint: "http://localhost:#{ns_bypass.port}/ns-auth"
        },
        app.id,
        tenant.id
      )

      socket = reconnect_socket(api_key)

      Bypass.expect_once(ns_bypass, "POST", "/ns-auth", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{ok: true}))
      end)

      assert {:ok, _reply, _socket} = subscribe_and_join(socket, "private-vip-room", %{})
    end
  end

  describe "join/3 - presence channels" do
    test "joins presence channel with auth endpoint approval", %{
      application: app,
      api_key: api_key
    } do
      bypass = Bypass.open()

      app
      |> Ecto.Changeset.change(channels_auth_endpoint: "http://localhost:#{bypass.port}/auth")
      |> Ricqchet.Repo.update!()

      socket = reconnect_socket(api_key)

      Bypass.expect_once(bypass, "POST", "/auth", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{ok: true}))
      end)

      assert {:ok, _reply, _socket} = subscribe_and_join(socket, "presence-lobby", %{})
    end

    test "rejects presence channel when auth fails", %{
      application: app,
      api_key: api_key
    } do
      bypass = Bypass.open()

      app
      |> Ecto.Changeset.change(channels_auth_endpoint: "http://localhost:#{bypass.port}/auth")
      |> Ricqchet.Repo.update!()

      socket = reconnect_socket(api_key)

      Bypass.expect_once(bypass, "POST", "/auth", fn conn ->
        Plug.Conn.resp(conn, 403, "Forbidden")
      end)

      assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, "presence-lobby", %{})
    end
  end

  describe "receiving events" do
    test "receives events broadcast to channel", %{socket: socket, application: app} do
      {:ok, _reply, _socket} = subscribe_and_join(socket, "event-room", %{})

      payload = %{
        id: Ecto.UUID.generate(),
        event: "new-message",
        data: %{"text" => "hello"},
        channel: "event-room",
        socket_id: nil
      }

      Phoenix.PubSub.broadcast(
        Ricqchet.PubSub,
        internal_topic(app.id, "event-room"),
        {:channel_event, payload}
      )

      assert_push "new-message", %{data: %{"text" => "hello"}, channel: "event-room"}
    end

    test "skips event when socket_id matches sender", %{
      socket: socket,
      application: app
    } do
      {:ok, _reply, _socket} = subscribe_and_join(socket, "skip-room", %{})

      # The socket_id should match what ChannelSocket.id/1 returns
      sender_socket_id = "channel_socket:#{app.id}:user_123"

      payload = %{
        id: Ecto.UUID.generate(),
        event: "my-event",
        data: %{"text" => "self"},
        channel: "skip-room",
        socket_id: sender_socket_id
      }

      Phoenix.PubSub.broadcast(
        Ricqchet.PubSub,
        internal_topic(app.id, "skip-room"),
        {:channel_event, payload}
      )

      refute_push "my-event", _, 200
    end
  end

  defp insert_event(app_id, tenant_id, channel, event_name, data \\ %{}) do
    %ChannelEvent{application_id: app_id, tenant_id: tenant_id}
    |> ChannelEvent.changeset(%{
      channel: channel,
      event_name: event_name,
      data: Jason.encode!(data),
      data_size_bytes: byte_size(Jason.encode!(data))
    })
    |> Ricqchet.Repo.insert!()
  end

  describe "missed-message recovery" do
    test "recovers missed events on rejoin with last_event_id", %{
      socket: socket,
      application: app,
      tenant: tenant
    } do
      e1 = insert_event(app.id, tenant.id, "recovery-room", "msg-1", %{text: "first"})
      insert_event(app.id, tenant.id, "recovery-room", "msg-2", %{text: "second"})
      insert_event(app.id, tenant.id, "recovery-room", "msg-3", %{text: "third"})

      {:ok, _reply, _socket} =
        subscribe_and_join(socket, "recovery-room", %{"last_event_id" => e1.id})

      assert_push "msg-2", %{data: %{"text" => "second"}, channel: "recovery-room"}
      assert_push "msg-3", %{data: %{"text" => "third"}, channel: "recovery-room"}
    end

    test "pushes recovery_failed when last_event_id not found", %{
      socket: socket
    } do
      fake_id = Ecto.UUID.generate()

      {:ok, _reply, _socket} =
        subscribe_and_join(socket, "recovery-room", %{"last_event_id" => fake_id})

      assert_push "ricqchet:recovery_failed", %{
        reason: "event_not_found",
        last_event_id: ^fake_id
      }
    end

    test "does not recover when no last_event_id provided", %{
      socket: socket,
      application: app,
      tenant: tenant
    } do
      insert_event(app.id, tenant.id, "no-recover", "msg-1")

      {:ok, _reply, _socket} = subscribe_and_join(socket, "no-recover", %{})

      refute_push "msg-1", _, 200
    end

    test "recovered events include sequence", %{
      socket: socket,
      application: app,
      tenant: tenant
    } do
      e1 = insert_event(app.id, tenant.id, "seq-room", "msg-1")
      insert_event(app.id, tenant.id, "seq-room", "msg-2")

      {:ok, _reply, _socket} =
        subscribe_and_join(socket, "seq-room", %{"last_event_id" => e1.id})

      assert_push "msg-2", %{sequence: seq}
      assert is_integer(seq)
    end
  end

  describe "cache channels" do
    test "sends cached event when cache_enabled and event exists", %{
      socket: socket,
      application: app,
      tenant: tenant
    } do
      Namespaces.create_namespace(
        %{pattern: "cache-*", history_enabled: true, cache_enabled: true},
        app.id,
        tenant.id
      )

      insert_event(app.id, tenant.id, "cache-room", "latest-msg", %{text: "cached"})

      {:ok, _reply, _socket} = subscribe_and_join(socket, "cache-room", %{})

      assert_push "ricqchet:cached_event", payload
      assert payload.data == %{"text" => "cached"}
      assert payload.channel == "cache-room"
      assert payload.event == "latest-msg"
      assert is_integer(payload.sequence)
      assert is_binary(payload.id)
    end

    test "does not send cached event when cache_enabled is false", %{
      socket: socket,
      application: app,
      tenant: tenant
    } do
      Namespaces.create_namespace(
        %{pattern: "nocache-*", history_enabled: true, cache_enabled: false},
        app.id,
        tenant.id
      )

      insert_event(app.id, tenant.id, "nocache-room", "msg", %{text: "hi"})

      {:ok, _reply, _socket} = subscribe_and_join(socket, "nocache-room", %{})

      refute_push "ricqchet:cached_event", _, 200
    end

    test "does not send cached event when no events exist", %{
      socket: socket,
      application: app,
      tenant: tenant
    } do
      Namespaces.create_namespace(
        %{pattern: "empty-*", history_enabled: true, cache_enabled: true},
        app.id,
        tenant.id
      )

      {:ok, _reply, _socket} = subscribe_and_join(socket, "empty-room", %{})

      refute_push "ricqchet:cached_event", _, 200
    end

    test "recovery takes priority over cache", %{
      socket: socket,
      application: app,
      tenant: tenant
    } do
      Namespaces.create_namespace(
        %{pattern: "recover-cache-*", history_enabled: true, cache_enabled: true},
        app.id,
        tenant.id
      )

      e1 = insert_event(app.id, tenant.id, "recover-cache-room", "msg-1", %{text: "first"})
      insert_event(app.id, tenant.id, "recover-cache-room", "msg-2", %{text: "second"})

      {:ok, _reply, _socket} =
        subscribe_and_join(socket, "recover-cache-room", %{"last_event_id" => e1.id})

      # Should get recovery, not cached event
      assert_push "msg-2", %{data: %{"text" => "second"}}
      refute_push "ricqchet:cached_event", _, 200
    end

    test "sends the most recent event as cached", %{
      socket: socket,
      application: app,
      tenant: tenant
    } do
      Namespaces.create_namespace(
        %{pattern: "multi-*", history_enabled: true, cache_enabled: true},
        app.id,
        tenant.id
      )

      insert_event(app.id, tenant.id, "multi-room", "old-msg", %{text: "old"})
      insert_event(app.id, tenant.id, "multi-room", "new-msg", %{text: "new"})

      {:ok, _reply, _socket} = subscribe_and_join(socket, "multi-room", %{})

      assert_push "ricqchet:cached_event", payload
      assert payload.event == "new-msg"
      assert payload.data == %{"text" => "new"}
    end
  end

  describe "client events" do
    setup %{application: app, api_key: api_key} do
      bypass = Bypass.open()

      app
      |> Ecto.Changeset.change(channels_auth_endpoint: "http://localhost:#{bypass.port}/auth")
      |> Ricqchet.Repo.update!()

      Bypass.stub(bypass, "POST", "/auth", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{ok: true}))
      end)

      socket = reconnect_socket(api_key)
      %{socket: socket, bypass: bypass}
    end

    test "sends client event on private channel", %{socket: socket} do
      {:ok, _reply, socket} = subscribe_and_join(socket, "private-client-room", %{})

      ref = push(socket, "client-typing", %{"user" => "alice"})
      assert_reply ref, :ok
    end

    test "rejects client event on public channel", %{api_key: api_key} do
      {:ok, _reply, pub_socket} =
        api_key
        |> reconnect_socket()
        |> subscribe_and_join("public-room", %{})

      ref = push(pub_socket, "client-typing", %{"user" => "alice"})
      assert_reply ref, :error, %{reason: "client_events_not_allowed"}
    end

    test "rejects non-client-prefixed events", %{api_key: api_key} do
      {:ok, _reply, joined_socket} =
        api_key
        |> reconnect_socket()
        |> subscribe_and_join("public-room", %{})

      ref = push(joined_socket, "custom-event", %{})
      assert_reply ref, :error, %{reason: "invalid_event"}
    end

    test "delivers client event to other subscribers and excludes the sender", %{
      socket: socket,
      api_key: api_key
    } do
      {:ok, _reply, sender_socket} = subscribe_and_join(socket, "private-broadcast-room", %{})

      {:ok, receiver_raw} =
        connect(ChannelSocket, %{"api_key" => api_key.api_key, "user_id" => "user_456"})

      {:ok, _reply, _receiver_socket} =
        subscribe_and_join(receiver_raw, "private-broadcast-room", %{})

      push(sender_socket, "client-typing", %{"active" => true})

      # The other subscriber receives the event tagged with the sender's identity...
      assert_push "client-typing", %{
        data: %{"active" => true},
        channel: "private-broadcast-room",
        user_id: "user_123"
      }

      # ...and the sender's own channel is excluded, so no duplicate is pushed.
      refute_push "client-typing", _, 200
    end

    test "isolates client events across applications", %{socket: socket} do
      {:ok, _reply, _joined} = subscribe_and_join(socket, "private-broadcast-room", %{})

      other_app_id = Ecto.UUID.generate()

      # A client event for another application's identically-named channel must not arrive.
      Phoenix.PubSub.broadcast(
        Ricqchet.PubSub,
        internal_topic(other_app_id, "private-broadcast-room"),
        {:client_event, "client-typing",
         %{data: %{"x" => 1}, channel: "private-broadcast-room", user_id: "intruder"}}
      )

      refute_push "client-typing", _, 200
    end

    test "rate limits excessive client events", %{
      socket: socket,
      application: app,
      tenant: tenant
    } do
      Namespaces.create_namespace(
        %{pattern: "private-rate-*", max_client_events_per_second: 2},
        app.id,
        tenant.id
      )

      {:ok, _reply, socket} = subscribe_and_join(socket, "private-rate-room", %{})

      # First 2 should succeed
      ref1 = push(socket, "client-ping", %{})
      assert_reply ref1, :ok
      ref2 = push(socket, "client-ping", %{})
      assert_reply ref2, :ok

      # Third should be rate limited
      ref3 = push(socket, "client-ping", %{})
      assert_reply ref3, :error, %{reason: "rate_limited"}
    end
  end

  describe "connection accounting" do
    test "channel join and leave do not change the per-socket connection count", %{
      socket: socket,
      application: app
    } do
      # The socket connected in setup is counted once.
      assert ConnectionTracker.get_count(app.id) == 1

      {:ok, _reply, joined} = subscribe_and_join(socket, "room-a", %{})
      assert ConnectionTracker.get_count(app.id) == 1

      Process.unlink(joined.channel_pid)
      ref = Process.monitor(joined.channel_pid)
      leave(joined)
      assert_receive {:DOWN, ^ref, :process, _, _}

      # Leaving the channel must NOT decrement the connection count — the count is
      # released per-socket (when the socket process dies), not per channel leave.
      assert ConnectionTracker.get_count(app.id) == 1
    end
  end

  describe "terminate/2" do
    test "decrements subscriber count on leave", %{socket: socket, application: app} do
      {:ok, _reply, socket} = subscribe_and_join(socket, "leave-room", %{})
      assert SubscriberTracker.get_count(app.id, "leave-room") == 1

      Process.unlink(socket.channel_pid)
      ref = Process.monitor(socket.channel_pid)
      leave(socket)
      assert_receive {:DOWN, ^ref, :process, _, _}
      assert SubscriberTracker.get_count(app.id, "leave-room") == 0
    end
  end
end
