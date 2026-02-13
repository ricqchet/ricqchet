defmodule Ricqchet.Channels.EventPublisherTest do
  use Ricqchet.DataCase, async: false

  alias Ricqchet.Channels.ChannelEvent
  alias Ricqchet.Channels.EventPublisher
  alias Ricqchet.Channels.NamespaceCache
  alias Ricqchet.Channels.Namespaces

  setup do
    NamespaceCache.invalidate_all()

    {:ok, %{tenant: tenant, application: app}} = create_tenant_with_api_key()

    {:ok, application} =
      app
      |> Ecto.Changeset.change(channels_enabled: true)
      |> Ricqchet.Repo.update()

    %{application: application, tenant: tenant}
  end

  describe "publish/5 without history" do
    test "publishes event via pubsub", %{application: app} do
      topic = "channels:app:#{app.id}:chat-room"
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, topic)

      {:ok, %{id: event_id}} =
        EventPublisher.publish(app.id, "chat-room", "new-message", %{"text" => "hello"})

      assert_receive {:channel_event, payload}
      assert payload.id == event_id
      assert payload.event == "new-message"
      assert payload.data == %{"text" => "hello"}
      assert payload.channel == "chat-room"
      assert payload.sequence == nil
    end

    test "does not persist event when no namespace matches", %{application: app} do
      EventPublisher.publish(app.id, "chat-room", "new-message", %{"text" => "hello"})

      assert Repo.aggregate(ChannelEvent, :count) == 0
    end

    test "does not persist event when namespace has history disabled", %{
      application: app,
      tenant: tenant
    } do
      Namespaces.create_namespace(
        %{pattern: "chat-*", priority: 10, history_enabled: false},
        app.id,
        tenant.id
      )

      EventPublisher.publish(app.id, "chat-room", "new-message", %{"text" => "hello"})

      assert Repo.aggregate(ChannelEvent, :count) == 0
    end
  end

  describe "publish/5 with history" do
    setup %{application: app, tenant: tenant} do
      {:ok, namespace} =
        Namespaces.create_namespace(
          %{pattern: "chat-*", priority: 10, history_enabled: true},
          app.id,
          tenant.id
        )

      %{namespace: namespace}
    end

    test "persists event when history is enabled", %{application: app, tenant: tenant} do
      {:ok, %{id: event_id}} =
        EventPublisher.publish(app.id, "chat-room", "new-message", %{"text" => "hello"},
          tenant_id: tenant.id
        )

      event = Repo.get!(ChannelEvent, event_id)
      assert event.channel == "chat-room"
      assert event.event_name == "new-message"
      assert event.data == Jason.encode!(%{"text" => "hello"})
      assert event.application_id == app.id
      assert event.tenant_id == tenant.id
      assert event.sequence != nil
    end

    test "includes sequence in pubsub payload", %{application: app, tenant: tenant} do
      topic = "channels:app:#{app.id}:chat-room"
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, topic)

      EventPublisher.publish(app.id, "chat-room", "new-message", %{"text" => "hello"},
        tenant_id: tenant.id
      )

      assert_receive {:channel_event, payload}
      assert is_integer(payload.sequence)
    end

    test "persists user_id and socket_id", %{application: app, tenant: tenant} do
      {:ok, %{id: event_id}} =
        EventPublisher.publish(app.id, "chat-room", "new-message", %{},
          tenant_id: tenant.id,
          user_id: "user_42",
          socket_id: "socket_abc"
        )

      event = Repo.get!(ChannelEvent, event_id)
      assert event.user_id == "user_42"
      assert event.socket_id == "socket_abc"
    end

    test "assigns monotonically increasing sequences", %{application: app, tenant: tenant} do
      {:ok, %{id: id1}} =
        EventPublisher.publish(app.id, "chat-room", "e1", %{}, tenant_id: tenant.id)

      {:ok, %{id: id2}} =
        EventPublisher.publish(app.id, "chat-room", "e2", %{}, tenant_id: tenant.id)

      {:ok, %{id: id3}} =
        EventPublisher.publish(app.id, "chat-room", "e3", %{}, tenant_id: tenant.id)

      e1 = Repo.get!(ChannelEvent, id1)
      e2 = Repo.get!(ChannelEvent, id2)
      e3 = Repo.get!(ChannelEvent, id3)

      assert e1.sequence < e2.sequence
      assert e2.sequence < e3.sequence
    end

    test "calculates data_size_bytes", %{application: app, tenant: tenant} do
      data = %{"message" => "hello world"}

      {:ok, %{id: event_id}} =
        EventPublisher.publish(app.id, "chat-room", "test", data, tenant_id: tenant.id)

      event = Repo.get!(ChannelEvent, event_id)
      assert event.data_size_bytes == byte_size(Jason.encode!(data))
    end
  end

  describe "history trimming" do
    test "trims events when history_max_events is set", %{application: app, tenant: tenant} do
      Namespaces.create_namespace(
        %{pattern: "trim-*", priority: 10, history_enabled: true, history_max_events: 3},
        app.id,
        tenant.id
      )

      for i <- 1..5 do
        EventPublisher.publish(app.id, "trim-room", "event-#{i}", %{i: i}, tenant_id: tenant.id)
      end

      import Ecto.Query

      query =
        from(e in ChannelEvent,
          where: e.application_id == ^app.id and e.channel == "trim-room",
          order_by: [asc: :sequence]
        )

      events = Repo.all(query)

      assert length(events) == 3

      event_names = Enum.map(events, & &1.event_name)
      assert event_names == ["event-3", "event-4", "event-5"]
    end

    test "does not trim when history_max_events is nil", %{application: app, tenant: tenant} do
      Namespaces.create_namespace(
        %{pattern: "notrim-*", priority: 10, history_enabled: true},
        app.id,
        tenant.id
      )

      for i <- 1..5 do
        EventPublisher.publish(app.id, "notrim-room", "event-#{i}", %{i: i}, tenant_id: tenant.id)
      end

      import Ecto.Query

      query =
        from(e in ChannelEvent,
          where: e.application_id == ^app.id and e.channel == "notrim-room"
        )

      count = Repo.aggregate(query, :count)

      assert count == 5
    end
  end
end
