defmodule Ricqchet.Channels.HistoryTest do
  use Ricqchet.DataCase, async: false

  alias Ricqchet.Channels.ChannelEvent
  alias Ricqchet.Channels.History
  alias Ricqchet.Repo

  setup do
    {:ok, %{tenant: tenant, application: app}} = create_tenant_with_api_key()

    {:ok, application} =
      app
      |> Ecto.Changeset.change(channels_enabled: true)
      |> Ricqchet.Repo.update()

    %{application: application, tenant: tenant}
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

  describe "get_events_since/4" do
    test "returns events after the given event", %{application: app, tenant: tenant} do
      e1 = insert_event(app.id, tenant.id, "chat", "msg-1", %{i: 1})
      e2 = insert_event(app.id, tenant.id, "chat", "msg-2", %{i: 2})
      e3 = insert_event(app.id, tenant.id, "chat", "msg-3", %{i: 3})

      {:ok, events} = History.get_events_since(app.id, "chat", e1.id)

      event_ids = Enum.map(events, & &1.id)
      assert event_ids == [e2.id, e3.id]
    end

    test "returns empty list when no events after reference", %{
      application: app,
      tenant: tenant
    } do
      e1 = insert_event(app.id, tenant.id, "chat", "msg-1")

      {:ok, events} = History.get_events_since(app.id, "chat", e1.id)
      assert events == []
    end

    test "returns error when reference event not found", %{application: app} do
      assert {:error, :event_not_found} =
               History.get_events_since(app.id, "chat", Ecto.UUID.generate())
    end

    test "respects limit option", %{application: app, tenant: tenant} do
      e1 = insert_event(app.id, tenant.id, "chat", "msg-1")

      for i <- 2..10 do
        insert_event(app.id, tenant.id, "chat", "msg-#{i}")
      end

      {:ok, events} = History.get_events_since(app.id, "chat", e1.id, limit: 3)
      assert length(events) == 3
    end

    test "caps limit at 100", %{application: app, tenant: tenant} do
      e1 = insert_event(app.id, tenant.id, "chat", "msg-1")

      for i <- 2..105 do
        insert_event(app.id, tenant.id, "chat", "msg-#{i}")
      end

      {:ok, events} = History.get_events_since(app.id, "chat", e1.id, limit: 200)
      assert length(events) == 100
    end

    test "scopes by application_id", %{tenant: tenant} do
      {:ok, other_app} =
        Ricqchet.Applications.create_application(tenant, %{name: "Other App"})

      e1 = insert_event(other_app.id, tenant.id, "chat", "msg-1")
      insert_event(other_app.id, tenant.id, "chat", "msg-2")

      {:ok, events} = History.get_events_since(other_app.id, "chat", e1.id)
      assert length(events) == 1
    end

    test "scopes by channel", %{application: app, tenant: tenant} do
      e1 = insert_event(app.id, tenant.id, "chat-1", "msg-1")
      insert_event(app.id, tenant.id, "chat-2", "msg-2")
      insert_event(app.id, tenant.id, "chat-1", "msg-3")

      {:ok, events} = History.get_events_since(app.id, "chat-1", e1.id)
      assert length(events) == 1
      assert hd(events).event_name == "msg-3"
    end
  end

  describe "get_recent_events/3" do
    test "returns recent events in ascending order", %{application: app, tenant: tenant} do
      e1 = insert_event(app.id, tenant.id, "chat", "msg-1")
      e2 = insert_event(app.id, tenant.id, "chat", "msg-2")
      e3 = insert_event(app.id, tenant.id, "chat", "msg-3")

      events = History.get_recent_events(app.id, "chat")
      event_ids = Enum.map(events, & &1.id)
      assert event_ids == [e1.id, e2.id, e3.id]
    end

    test "respects limit and returns most recent", %{application: app, tenant: tenant} do
      for i <- 1..5 do
        insert_event(app.id, tenant.id, "chat", "msg-#{i}")
      end

      events = History.get_recent_events(app.id, "chat", limit: 3)
      assert length(events) == 3

      event_names = Enum.map(events, & &1.event_name)
      assert event_names == ["msg-3", "msg-4", "msg-5"]
    end

    test "returns empty list for channel with no events", %{application: app} do
      events = History.get_recent_events(app.id, "nonexistent")
      assert events == []
    end

    test "scopes by application_id and channel", %{application: app, tenant: tenant} do
      insert_event(app.id, tenant.id, "chat-1", "msg-1")
      insert_event(app.id, tenant.id, "chat-2", "msg-2")
      insert_event(app.id, tenant.id, "chat-1", "msg-3")

      events = History.get_recent_events(app.id, "chat-1")
      assert length(events) == 2
      assert Enum.all?(events, &(&1.channel == "chat-1"))
    end
  end
end
