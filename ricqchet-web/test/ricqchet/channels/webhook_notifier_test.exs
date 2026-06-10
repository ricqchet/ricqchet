defmodule Ricqchet.Channels.WebhookNotifierTest do
  use Ricqchet.DataCase, async: true

  alias Ricqchet.Channels.Namespaces
  alias Ricqchet.Channels.WebhookNotifier

  setup do
    {:ok, %{tenant: tenant, application: app}} =
      create_tenant_with_api_key(%{}, %{channels_enabled: true})

    %{tenant: tenant, application: app}
  end

  describe "enqueue/2" do
    test "inserts an Oban job", %{application: app} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %Oban.Job{}} =
                 WebhookNotifier.enqueue("channel:occupied", %{
                   application_id: app.id,
                   channel_name: "test-channel"
                 })

        assert_enqueued(
          worker: WebhookNotifier,
          args: %{
            event: "channel:occupied",
            application_id: app.id,
            channel_name: "test-channel"
          }
        )
      end)
    end

    test "includes user info for presence events", %{application: app} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _job} =
                 WebhookNotifier.enqueue("member:added", %{
                   application_id: app.id,
                   channel_name: "presence-room",
                   user_id: "user-123",
                   user_info: %{"name" => "Alice"}
                 })

        assert_enqueued(
          worker: WebhookNotifier,
          args: %{
            event: "member:added",
            user_id: "user-123",
            user_info: %{"name" => "Alice"}
          }
        )
      end)
    end
  end

  describe "perform/1" do
    test "sends webhook to application URL", %{application: app, tenant: tenant} do
      bypass = Bypass.open()
      url = "http://localhost:#{bypass.port}/webhook"

      app
      |> Ecto.Changeset.change(channels_webhook_url: url)
      |> Repo.update!()

      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["event"] == "channel:occupied"
        assert payload["channel"] == "test-channel"

        if tenant.signing_secret do
          assert Plug.Conn.get_req_header(conn, "x-ricqchet-signature") != []
        end

        Plug.Conn.resp(conn, 200, "ok")
      end)

      assert :ok =
               perform_job(WebhookNotifier, %{
                 event: "channel:occupied",
                 application_id: app.id,
                 channel_name: "test-channel",
                 timestamp: DateTime.to_iso8601(DateTime.utc_now())
               })
    end

    test "sends webhook to namespace URL when configured", %{application: app, tenant: tenant} do
      bypass = Bypass.open()
      namespace_url = "http://localhost:#{bypass.port}/ns-webhook"

      {:ok, _ns} =
        Namespaces.create_namespace(
          %{pattern: "chat-*", webhook_url: namespace_url},
          app.id,
          tenant.id
        )

      Bypass.expect_once(bypass, "POST", "/ns-webhook", fn conn ->
        Plug.Conn.resp(conn, 200, "ok")
      end)

      assert :ok =
               perform_job(WebhookNotifier, %{
                 event: "channel:occupied",
                 application_id: app.id,
                 channel_name: "chat-room",
                 timestamp: DateTime.to_iso8601(DateTime.utc_now())
               })
    end

    test "skips when no webhook URL configured", %{application: app} do
      assert :ok =
               perform_job(WebhookNotifier, %{
                 event: "channel:occupied",
                 application_id: app.id,
                 channel_name: "test-channel",
                 timestamp: DateTime.to_iso8601(DateTime.utc_now())
               })
    end

    test "includes user data for member events", %{application: app} do
      bypass = Bypass.open()
      url = "http://localhost:#{bypass.port}/webhook"

      app
      |> Ecto.Changeset.change(channels_webhook_url: url)
      |> Repo.update!()

      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["event"] == "member:added"
        assert payload["user_id"] == "user-456"
        assert payload["user_info"] == %{"name" => "Bob"}

        Plug.Conn.resp(conn, 200, "ok")
      end)

      assert :ok =
               perform_job(WebhookNotifier, %{
                 event: "member:added",
                 application_id: app.id,
                 channel_name: "presence-room",
                 user_id: "user-456",
                 user_info: %{"name" => "Bob"},
                 timestamp: DateTime.to_iso8601(DateTime.utc_now())
               })
    end

    test "retries on non-2xx response", %{application: app} do
      bypass = Bypass.open()
      url = "http://localhost:#{bypass.port}/webhook"

      app
      |> Ecto.Changeset.change(channels_webhook_url: url)
      |> Repo.update!()

      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        Plug.Conn.resp(conn, 500, "error")
      end)

      assert {:error, "HTTP 500"} =
               perform_job(WebhookNotifier, %{
                 event: "channel:vacated",
                 application_id: app.id,
                 channel_name: "test-channel",
                 timestamp: DateTime.to_iso8601(DateTime.utc_now())
               })
    end
  end
end
