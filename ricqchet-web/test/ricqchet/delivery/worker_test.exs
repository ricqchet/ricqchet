defmodule Ricqchet.Delivery.WorkerTest do
  use Ricqchet.DataCase, async: false

  alias Ricqchet.Delivery.Worker
  alias Ricqchet.Messages

  setup do
    {:ok, %{tenant: tenant, application: application}} =
      create_tenant_with_api_key()

    bypass = Bypass.open()

    %{tenant: tenant, application: application, bypass: bypass}
  end

  describe "channel broadcast on delivery" do
    test "broadcasts relay:message event on successful delivery", %{
      tenant: tenant,
      application: application,
      bypass: bypass
    } do
      {:ok, message} =
        Messages.create(tenant, %{
          destination_url: "http://localhost:#{bypass.port}/webhook",
          payload: ~s({"test": true}),
          headers: %{"Ricqchet-Channel" => "my-channel"},
          application_id: application.id
        })

      topic = "channels:app:#{application.id}:my-channel"
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, topic)

      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"ok": true}))
      end)

      perform_job(Worker, %{message_id: message.id})

      assert_receive {:channel_event, payload}, 1000
      assert payload.event == "relay:message"
      assert payload.channel == "my-channel"
      assert payload.data.message_id == message.id
    end

    test "does not broadcast when no Ricqchet-Channel header", %{
      tenant: tenant,
      application: application,
      bypass: bypass
    } do
      {:ok, message} =
        Messages.create(tenant, %{
          destination_url: "http://localhost:#{bypass.port}/webhook",
          payload: ~s({"test": true}),
          headers: %{"X-Custom" => "value"},
          application_id: application.id
        })

      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"ok": true}))
      end)

      perform_job(Worker, %{message_id: message.id})

      refute_receive {:channel_event, _}, 200
    end

    test "handles case-insensitive header matching", %{
      tenant: tenant,
      application: application,
      bypass: bypass
    } do
      {:ok, message} =
        Messages.create(tenant, %{
          destination_url: "http://localhost:#{bypass.port}/webhook",
          payload: ~s({"test": true}),
          headers: %{"ricqchet-channel" => "lowercase-channel"},
          application_id: application.id
        })

      topic = "channels:app:#{application.id}:lowercase-channel"
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, topic)

      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"ok": true}))
      end)

      perform_job(Worker, %{message_id: message.id})

      assert_receive {:channel_event, payload}, 1000
      assert payload.event == "relay:message"
      assert payload.channel == "lowercase-channel"
    end

    test "does not broadcast on failed delivery", %{
      tenant: tenant,
      application: application,
      bypass: bypass
    } do
      {:ok, message} =
        Messages.create(tenant, %{
          destination_url: "http://localhost:#{bypass.port}/webhook",
          payload: ~s({"test": true}),
          headers: %{"Ricqchet-Channel" => "my-channel"},
          application_id: application.id
        })

      topic = "channels:app:#{application.id}:my-channel"
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, topic)

      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        Plug.Conn.resp(conn, 500, ~s({"error": "server error"}))
      end)

      perform_job(Worker, %{message_id: message.id})

      refute_receive {:channel_event, _}, 200
    end

    test "delivery succeeds even if channel broadcast fails", %{
      tenant: tenant,
      application: application,
      bypass: bypass
    } do
      {:ok, message} =
        Messages.create(tenant, %{
          destination_url: "http://localhost:#{bypass.port}/webhook",
          payload: ~s({"test": true}),
          headers: %{"Ricqchet-Channel" => ""},
          application_id: application.id
        })

      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"ok": true}))
      end)

      # Should not raise - broadcast failure is caught by rescue
      assert :ok = perform_job(Worker, %{message_id: message.id})

      # Verify delivery was still marked as successful
      updated = Messages.get!(message.id)
      assert updated.status == "delivered"
    end

    test "does not broadcast when headers is nil", %{
      tenant: tenant,
      bypass: bypass
    } do
      {:ok, message} =
        Messages.create(tenant, %{
          destination_url: "http://localhost:#{bypass.port}/webhook",
          payload: ~s({"test": true})
        })

      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"ok": true}))
      end)

      # Should complete without errors even with no headers
      assert :ok = perform_job(Worker, %{message_id: message.id})
    end
  end
end
