defmodule RicqchetWeb.Channels.PubsubChannelTest do
  use RicqchetWeb.ChannelCase, async: false

  import Ricqchet.DataCase, only: [create_tenant_with_api_key: 0]

  alias Ricqchet.Channels.SubscriberTracker
  alias RicqchetWeb.Channels.ChannelSocket

  setup do
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

    %{socket: socket, application: application, tenant: tenant}
  end

  describe "join/3" do
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

    test "rejects private channel in Phase 1", %{socket: socket, application: app} do
      topic = "channels:app:#{app.id}:private-room"

      assert {:error, %{reason: "channel_type_not_supported"}} =
               subscribe_and_join(socket, topic, %{})
    end

    test "rejects presence channel in Phase 1", %{socket: socket, application: app} do
      topic = "channels:app:#{app.id}:presence-lobby"

      assert {:error, %{reason: "channel_type_not_supported"}} =
               subscribe_and_join(socket, topic, %{})
    end

    test "rejects invalid channel name", %{socket: socket, application: app} do
      topic = "channels:app:#{app.id}:invalid name!"

      assert {:error, %{reason: "invalid_channel_name"}} =
               subscribe_and_join(socket, topic, %{})
    end

    test "rejects channel name that is too long", %{socket: socket, application: app} do
      long_name = String.duplicate("a", 165)
      topic = "channels:app:#{app.id}:#{long_name}"

      assert {:error, %{reason: "invalid_channel_name"}} =
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
