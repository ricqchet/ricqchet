defmodule RicqchetWeb.Channels.PubsubChannelTest do
  use RicqchetWeb.ChannelCase, async: false

  import Ricqchet.DataCase, only: [create_tenant_with_api_key: 0]

  alias Ricqchet.Channels.ChannelEvent
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

  describe "join/3 - public channels" do
    test "joins a public channel", %{socket: socket, application: app} do
      topic = "channels:app:#{app.id}:chat-room"
      assert {:ok, _reply, _socket} = subscribe_and_join(socket, topic, %{})
    end

    test "tracks subscriber count on join", %{socket: socket, application: app} do
      topic = "channels:app:#{app.id}:tracked-room"
      {:ok, _reply, _socket} = subscribe_and_join(socket, topic, %{})
      assert SubscriberTracker.get_count(app.id, "tracked-room") == 1
    end

    test "rejects join when app_id doesn't match", %{socket: socket} do
      other_app_id = Ecto.UUID.generate()
      topic = "channels:app:#{other_app_id}:chat-room"
      assert {:error, %{reason: "unauthorized"}} = subscribe_and_join(socket, topic, %{})
    end

    test "rejects invalid channel name", %{socket: socket, application: app} do
      topic = "channels:app:#{app.id}:invalid name!"

      assert {:error, %{reason: "invalid channel name" <> _}} =
               subscribe_and_join(socket, topic, %{})
    end

    test "rejects channel name that is too long", %{socket: socket, application: app} do
      long_name = String.duplicate("a", 165)
      topic = "channels:app:#{app.id}:#{long_name}"

      assert {:error, %{reason: "invalid channel name" <> _}} =
               subscribe_and_join(socket, topic, %{})
    end

    test "accepts maximum length channel name", %{socket: socket, application: app} do
      name = String.duplicate("a", 164)
      topic = "channels:app:#{app.id}:#{name}"
      assert {:ok, _reply, _socket} = subscribe_and_join(socket, topic, %{})
    end

    test "rejects invalid topic format", %{socket: socket} do
      assert {:error, %{reason: "invalid_topic"}} =
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

      topic = "channels:app:#{app.id}:private-room"
      assert {:ok, _reply, _socket} = subscribe_and_join(socket, topic, %{})
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

      topic = "channels:app:#{app.id}:private-room"
      assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, topic, %{})
    end

    test "rejects private channel when no auth endpoint configured", %{
      socket: socket,
      application: app
    } do
      topic = "channels:app:#{app.id}:private-room"

      assert {:error, %{reason: "auth_endpoint_not_configured"}} =
               subscribe_and_join(socket, topic, %{})
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

      topic = "channels:app:#{app.id}:private-room"
      assert {:error, %{reason: "auth_unavailable"}} = subscribe_and_join(socket, topic, %{})
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

      topic = "channels:app:#{app.id}:private-vip-room"
      assert {:ok, _reply, _socket} = subscribe_and_join(socket, topic, %{})
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

      topic = "channels:app:#{app.id}:presence-lobby"
      assert {:ok, _reply, _socket} = subscribe_and_join(socket, topic, %{})
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

      topic = "channels:app:#{app.id}:presence-lobby"
      assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, topic, %{})
    end
  end

  describe "receiving events" do
    test "receives events broadcast to channel", %{socket: socket, application: app} do
      topic = "channels:app:#{app.id}:event-room"
      {:ok, _reply, _socket} = subscribe_and_join(socket, topic, %{})

      payload = %{
        id: Ecto.UUID.generate(),
        event: "new-message",
        data: %{"text" => "hello"},
        channel: "event-room",
        socket_id: nil
      }

      Phoenix.PubSub.broadcast(Ricqchet.PubSub, topic, {:channel_event, payload})

      assert_push "new-message", %{data: %{"text" => "hello"}, channel: "event-room"}
    end

    test "skips event when socket_id matches sender", %{
      socket: socket,
      application: app
    } do
      topic = "channels:app:#{app.id}:skip-room"
      {:ok, _reply, _socket} = subscribe_and_join(socket, topic, %{})

      # The socket_id should match what ChannelSocket.id/1 returns
      sender_socket_id = "channel_socket:#{app.id}:user_123"

      payload = %{
        id: Ecto.UUID.generate(),
        event: "my-event",
        data: %{"text" => "self"},
        channel: "skip-room",
        socket_id: sender_socket_id
      }

      Phoenix.PubSub.broadcast(Ricqchet.PubSub, topic, {:channel_event, payload})

      refute_push "my-event", _, 200
    end
  end

  describe "missed-message recovery" do
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

    test "recovers missed events on rejoin with last_event_id", %{
      socket: socket,
      application: app,
      tenant: tenant
    } do
      e1 = insert_event(app.id, tenant.id, "recovery-room", "msg-1", %{text: "first"})
      insert_event(app.id, tenant.id, "recovery-room", "msg-2", %{text: "second"})
      insert_event(app.id, tenant.id, "recovery-room", "msg-3", %{text: "third"})

      topic = "channels:app:#{app.id}:recovery-room"

      {:ok, _reply, _socket} =
        subscribe_and_join(socket, topic, %{"last_event_id" => e1.id})

      assert_push "msg-2", %{data: %{"text" => "second"}, channel: "recovery-room"}
      assert_push "msg-3", %{data: %{"text" => "third"}, channel: "recovery-room"}
    end

    test "pushes recovery_failed when last_event_id not found", %{
      socket: socket,
      application: app
    } do
      topic = "channels:app:#{app.id}:recovery-room"
      fake_id = Ecto.UUID.generate()

      {:ok, _reply, _socket} =
        subscribe_and_join(socket, topic, %{"last_event_id" => fake_id})

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

      topic = "channels:app:#{app.id}:no-recover"
      {:ok, _reply, _socket} = subscribe_and_join(socket, topic, %{})

      refute_push "msg-1", _, 200
    end

    test "recovered events include sequence", %{
      socket: socket,
      application: app,
      tenant: tenant
    } do
      e1 = insert_event(app.id, tenant.id, "seq-room", "msg-1")
      insert_event(app.id, tenant.id, "seq-room", "msg-2")

      topic = "channels:app:#{app.id}:seq-room"

      {:ok, _reply, _socket} =
        subscribe_and_join(socket, topic, %{"last_event_id" => e1.id})

      assert_push "msg-2", %{sequence: seq}
      assert is_integer(seq)
    end
  end

  describe "terminate/2" do
    test "decrements subscriber count on leave", %{socket: socket, application: app} do
      topic = "channels:app:#{app.id}:leave-room"
      {:ok, _reply, socket} = subscribe_and_join(socket, topic, %{})
      assert SubscriberTracker.get_count(app.id, "leave-room") == 1

      Process.unlink(socket.channel_pid)
      ref = Process.monitor(socket.channel_pid)
      leave(socket)
      assert_receive {:DOWN, ^ref, :process, _, _}
      assert SubscriberTracker.get_count(app.id, "leave-room") == 0
    end
  end
end
