defmodule Ricqchet.Channels.CleanupWorkerTest do
  use Ricqchet.DataCase, async: true

  alias Ricqchet.Channels.ChannelEvent
  alias Ricqchet.Channels.CleanupWorker
  alias Ricqchet.Channels.Namespaces

  describe "perform/1" do
    setup do
      {:ok, %{tenant: tenant, application: app}} = create_tenant_with_api_key()
      %{application: app, tenant: tenant}
    end

    test "deletes events older than TTL", %{application: app, tenant: tenant} do
      {:ok, _ns} =
        Namespaces.create_namespace(
          %{
            pattern: "*",
            history_enabled: true,
            history_ttl_seconds: 3600
          },
          app.id,
          tenant.id
        )

      old_event = insert_event(app.id, tenant.id, "chat-room", "msg", %{text: "old"})

      # Backdate the event to 2 hours ago (relative to DB now() for consistency)
      ChannelEvent
      |> where([e], e.id == ^old_event.id)
      |> Repo.update_all(
        set: [inserted_at: dynamic([e], fragment("now() - interval '7200 seconds'"))]
      )

      recent_event = insert_event(app.id, tenant.id, "chat-room", "msg", %{text: "recent"})

      assert :ok = perform_job(CleanupWorker, %{})

      assert Repo.get(ChannelEvent, recent_event.id) != nil
      assert Repo.get(ChannelEvent, old_event.id) == nil
    end

    test "trims channels exceeding max events", %{application: app, tenant: tenant} do
      {:ok, _ns} =
        Namespaces.create_namespace(
          %{
            pattern: "chat-*",
            history_enabled: true,
            history_max_events: 2
          },
          app.id,
          tenant.id
        )

      event1 = insert_event(app.id, tenant.id, "chat-room", "msg", %{n: 1})
      event2 = insert_event(app.id, tenant.id, "chat-room", "msg", %{n: 2})
      event3 = insert_event(app.id, tenant.id, "chat-room", "msg", %{n: 3})

      assert :ok = perform_job(CleanupWorker, %{})

      # Oldest should be deleted, 2 newest kept
      assert Repo.get(ChannelEvent, event1.id) == nil
      assert Repo.get(ChannelEvent, event2.id) != nil
      assert Repo.get(ChannelEvent, event3.id) != nil
    end

    test "respects namespace pattern matching", %{application: app, tenant: tenant} do
      {:ok, _ns} =
        Namespaces.create_namespace(
          %{
            pattern: "chat-*",
            history_enabled: true,
            history_max_events: 1
          },
          app.id,
          tenant.id
        )

      # Events in matching channel
      chat_event1 = insert_event(app.id, tenant.id, "chat-room", "msg", %{n: 1})
      chat_event2 = insert_event(app.id, tenant.id, "chat-room", "msg", %{n: 2})

      # Events in non-matching channel
      other_event1 = insert_event(app.id, tenant.id, "notifications", "alert", %{n: 1})
      other_event2 = insert_event(app.id, tenant.id, "notifications", "alert", %{n: 2})

      assert :ok = perform_job(CleanupWorker, %{})

      # Chat channel trimmed to 1
      assert Repo.get(ChannelEvent, chat_event1.id) == nil
      assert Repo.get(ChannelEvent, chat_event2.id) != nil

      # Notifications channel untouched
      assert Repo.get(ChannelEvent, other_event1.id) != nil
      assert Repo.get(ChannelEvent, other_event2.id) != nil
    end

    test "no-op when no namespaces have cleanup config", %{application: app, tenant: tenant} do
      {:ok, _ns} =
        Namespaces.create_namespace(
          %{
            pattern: "*",
            history_enabled: false
          },
          app.id,
          tenant.id
        )

      event = insert_event(app.id, tenant.id, "chat-room", "msg", %{text: "hi"})

      assert :ok = perform_job(CleanupWorker, %{})
      assert Repo.get(ChannelEvent, event.id) != nil
    end

    test "no-op when history is disabled even with TTL set", %{
      application: app,
      tenant: tenant
    } do
      {:ok, _ns} =
        Namespaces.create_namespace(
          %{
            pattern: "*",
            history_enabled: false,
            history_ttl_seconds: 1
          },
          app.id,
          tenant.id
        )

      event = insert_event(app.id, tenant.id, "chat-room", "msg", %{text: "hi"})

      # Backdate the event (relative to DB now() for consistency)
      ChannelEvent
      |> where([e], e.id == ^event.id)
      |> Repo.update_all(
        set: [inserted_at: dynamic([e], fragment("now() - interval '7200 seconds'"))]
      )

      assert :ok = perform_job(CleanupWorker, %{})
      assert Repo.get(ChannelEvent, event.id) != nil
    end

    test "handles both TTL and max events on same namespace", %{
      application: app,
      tenant: tenant
    } do
      {:ok, _ns} =
        Namespaces.create_namespace(
          %{
            pattern: "*",
            history_enabled: true,
            history_ttl_seconds: 3600,
            history_max_events: 5
          },
          app.id,
          tenant.id
        )

      old_event = insert_event(app.id, tenant.id, "chat-room", "msg", %{text: "old"})

      ChannelEvent
      |> where([e], e.id == ^old_event.id)
      |> Repo.update_all(
        set: [inserted_at: dynamic([e], fragment("now() - interval '7200 seconds'"))]
      )

      recent_event = insert_event(app.id, tenant.id, "chat-room", "msg", %{text: "recent"})

      assert :ok = perform_job(CleanupWorker, %{})

      # Old event deleted by TTL
      assert Repo.get(ChannelEvent, old_event.id) == nil
      # Recent event kept (under max_events)
      assert Repo.get(ChannelEvent, recent_event.id) != nil
    end
  end

  defp insert_event(app_id, tenant_id, channel, event_name, data) do
    %ChannelEvent{application_id: app_id, tenant_id: tenant_id}
    |> ChannelEvent.changeset(%{
      channel: channel,
      event_name: event_name,
      data: Jason.encode!(data),
      data_size_bytes: byte_size(Jason.encode!(data))
    })
    |> Repo.insert!()
  end
end
