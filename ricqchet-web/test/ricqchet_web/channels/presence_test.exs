defmodule RicqchetWeb.Channels.PresenceTest do
  use RicqchetWeb.ChannelCase, async: false

  import Ricqchet.DataCase, only: [create_tenant_with_api_key: 0]

  alias Ricqchet.Channels.NamespaceCache
  alias RicqchetWeb.Channels.ChannelSocket
  alias RicqchetWeb.Channels.Presence

  setup do
    NamespaceCache.invalidate_all()

    {:ok, %{tenant: _tenant, application: app, api_key: api_key}} =
      create_tenant_with_api_key()

    bypass = Bypass.open()

    {:ok, application} =
      app
      |> Ecto.Changeset.change(
        channels_enabled: true,
        channels_auth_endpoint: "http://localhost:#{bypass.port}/auth"
      )
      |> Ricqchet.Repo.update()

    Bypass.stub(bypass, "POST", "/auth", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{ok: true}))
    end)

    %{application: application, api_key: api_key, bypass: bypass}
  end

  defp connect_user(api_key, user_id, user_info \\ %{}) do
    {:ok, socket} =
      connect(ChannelSocket, %{
        "api_key" => api_key.api_key,
        "user_id" => user_id,
        "user_info" => Jason.encode!(user_info)
      })

    socket
  end

  describe "presence tracking" do
    test "receives presence_state after joining presence channel", %{api_key: api_key} do
      socket = connect_user(api_key, "user_1", %{name: "Alice"})

      {:ok, _reply, _socket} = subscribe_and_join(socket, "presence-lobby", %{})

      assert_push "presence_state", state
      assert Map.has_key?(state, "user_1")
    end

    test "tracks user_info in presence metadata", %{api_key: api_key} do
      socket = connect_user(api_key, "user_1", %{name: "Alice"})

      {:ok, _reply, _socket} = subscribe_and_join(socket, "presence-meta-room", %{})

      assert_push "presence_state", state
      user_data = state["user_1"]
      metas = user_data.metas
      assert length(metas) == 1
      meta = hd(metas)
      assert meta.user_info == %{"name" => "Alice"}
      assert is_integer(meta.joined_at)
    end

    test "receives presence_diff when another user joins", %{api_key: api_key} do
      socket1 = connect_user(api_key, "user_1")

      {:ok, _reply, _socket1} = subscribe_and_join(socket1, "presence-diff-room", %{})

      # Consume initial presence messages
      assert_push "presence_state", _state
      assert_push "presence_diff", %{joins: %{"user_1" => _}}

      socket2 = connect_user(api_key, "user_2")
      {:ok, _reply, _socket2} = subscribe_and_join(socket2, "presence-diff-room", %{})

      assert_push "presence_diff", %{joins: %{"user_2" => _}}
    end

    test "receives presence_diff when user leaves", %{api_key: api_key} do
      socket1 = connect_user(api_key, "user_1")

      {:ok, _reply, _socket1} = subscribe_and_join(socket1, "presence-leave-room", %{})
      assert_push "presence_state", _state

      socket2 = connect_user(api_key, "user_2")
      {:ok, _reply, socket2_joined} = subscribe_and_join(socket2, "presence-leave-room", %{})

      # Consume join diffs
      assert_push "presence_diff", _join_diff1
      assert_push "presence_diff", _join_diff2

      # Leave
      Process.unlink(socket2_joined.channel_pid)
      ref = Process.monitor(socket2_joined.channel_pid)
      leave(socket2_joined)
      assert_receive {:DOWN, ^ref, :process, _, _}

      assert_push "presence_diff", %{leaves: %{"user_2" => _}}
    end

    test "presence list shows connected users", %{application: app, api_key: api_key} do
      socket = connect_user(api_key, "user_1")

      {:ok, _reply, _joined_socket} = subscribe_and_join(socket, "presence-list-room", %{})
      assert_push "presence_state", _state

      Process.sleep(50)

      # Presence is tracked on the internal application-scoped topic, not the bare
      # client topic, so list against the internal topic.
      presence_list = Presence.list("channels:app:#{app.id}:presence-list-room")
      assert Map.has_key?(presence_list, "user_1")
    end

    test "isolates presence diffs across applications", %{application: app, api_key: api_key} do
      socket = connect_user(api_key, "user_1")
      {:ok, _reply, _joined} = subscribe_and_join(socket, "presence-lobby", %{})

      assert_push "presence_state", _state
      assert_push "presence_diff", %{joins: %{"user_1" => _}}

      other_app_id = Ecto.UUID.generate()

      # A diff for another application's identically-named presence channel must not
      # reach this subscriber — presence is scoped to the internal app topic.
      foreign = "channels:app:#{other_app_id}:presence-lobby"

      Phoenix.PubSub.broadcast(Ricqchet.PubSub, foreign, %Phoenix.Socket.Broadcast{
        topic: foreign,
        event: "presence_diff",
        payload: %{joins: %{"intruder" => %{metas: []}}, leaves: %{}}
      })

      refute_push "presence_diff", %{joins: %{"intruder" => _}}, 200

      # A diff on this application's internal topic, however, is delivered.
      own = "channels:app:#{app.id}:presence-lobby"

      Phoenix.PubSub.broadcast(Ricqchet.PubSub, own, %Phoenix.Socket.Broadcast{
        topic: own,
        event: "presence_diff",
        payload: %{joins: %{"friend" => %{metas: []}}, leaves: %{}}
      })

      assert_push "presence_diff", %{joins: %{"friend" => _}}
    end
  end
end
