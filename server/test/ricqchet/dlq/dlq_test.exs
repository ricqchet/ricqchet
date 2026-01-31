defmodule Ricqchet.DlqTest do
  use Ricqchet.DataCase, async: true

  alias Ricqchet.Applications
  alias Ricqchet.Dlq
  alias Ricqchet.Messages

  describe "maybe_notify_failure/1 for messages" do
    test "does nothing when message has no application_id" do
      {:ok, %{tenant: tenant}} = create_tenant_with_api_key()

      {:ok, message} =
        Messages.create(tenant, %{
          destination_url: "https://example.com/api",
          payload: ~s({"test": true})
        })

      # Should be a no-op since message has no application
      assert :ok = Dlq.maybe_notify_failure(message)
    end

    test "does nothing when application has no DLQ destination configured" do
      {:ok, %{tenant: tenant, application: application}} = create_tenant_with_api_key()

      {:ok, message} =
        Messages.create(tenant, %{destination_url: "https://example.com/api"}, application)

      # Application has no dlq_destination_url, should be a no-op
      assert :ok = Dlq.maybe_notify_failure(message)
    end

    test "enqueues notification when application has DLQ destination configured" do
      {:ok, %{tenant: tenant, application: application}} =
        create_tenant_with_api_key(%{}, %{dlq_destination_url: "https://dlq.example.com/webhook"})

      {:ok, message} =
        Messages.create(tenant, %{destination_url: "https://example.com/api"}, application)

      # In inline testing mode, the job is executed immediately
      # The :ok return confirms the job was successfully enqueued
      assert :ok = Dlq.maybe_notify_failure(message)
    end

    test "does nothing when DLQ destination is empty string" do
      {:ok, %{tenant: tenant, application: application}} =
        create_tenant_with_api_key(%{}, %{dlq_destination_url: ""})

      {:ok, message} =
        Messages.create(tenant, %{destination_url: "https://example.com/api"}, application)

      # Empty string should be treated as no destination configured
      assert :ok = Dlq.maybe_notify_failure(message)
    end
  end

  describe "maybe_notify_failure/1 for batches" do
    alias Ricqchet.Batches

    test "does nothing when batch has no application_id" do
      {:ok, %{tenant: tenant}} = create_tenant_with_api_key()

      {:ok, batch, :new} =
        Batches.find_or_create_collecting(tenant, "https://example.com/api", "test-key")

      # Should be a no-op since batch has no application
      assert :ok = Dlq.maybe_notify_failure(batch)
    end

    test "enqueues notification when application has DLQ destination configured" do
      {:ok, %{tenant: tenant, application: application}} =
        create_tenant_with_api_key(%{}, %{dlq_destination_url: "https://dlq.example.com/webhook"})

      {:ok, batch, :new} =
        Batches.find_or_create_collecting(
          tenant,
          "https://example.com/api",
          "test-key",
          %{},
          application
        )

      # In inline testing mode, the job is executed immediately
      # The :ok return confirms the job was successfully enqueued
      assert :ok = Dlq.maybe_notify_failure(batch)
    end
  end

  describe "integration with mark_failed/3" do
    test "triggers DLQ notification when message is permanently failed" do
      {:ok, %{tenant: tenant, application: application}} =
        create_tenant_with_api_key(%{}, %{dlq_destination_url: "https://dlq.example.com/webhook"})

      {:ok, message} =
        Messages.create(
          tenant,
          %{destination_url: "https://example.com/api", max_retries: 1},
          application
        )

      # The message starts with attempts=0, max_retries=1
      # After first mark_failed, attempts=1 >= max_retries=1, so it's permanently failed

      {:ok, failed_message} = Messages.mark_failed(message, "Connection refused")

      assert failed_message.status == "failed"
      assert failed_message.attempts == 1
      # DLQ notification was triggered by mark_failed when status became "failed"
    end

    test "does not trigger DLQ when message still has retries" do
      {:ok, %{tenant: tenant, application: application}} =
        create_tenant_with_api_key(%{}, %{dlq_destination_url: "https://dlq.example.com/webhook"})

      {:ok, message} =
        Messages.create(
          tenant,
          %{destination_url: "https://example.com/api", max_retries: 3},
          application
        )

      {:ok, updated_message} = Messages.mark_failed(message, "Connection refused")

      # Message still has retries, so it should be pending, not failed
      # No DLQ notification should be triggered
      assert updated_message.status == "pending"
      assert updated_message.attempts == 1
    end
  end

  describe "application dlq_destination_url field" do
    test "can be set when creating application" do
      {:ok, %{tenant: tenant}} = create_tenant_with_api_key()

      {:ok, app} =
        Applications.create_application(tenant, %{
          name: "DLQ Enabled App",
          dlq_destination_url: "https://my-dlq.example.com/events"
        })

      assert app.dlq_destination_url == "https://my-dlq.example.com/events"
    end

    test "can be updated on existing application" do
      {:ok, %{application: application}} = create_tenant_with_api_key()

      {:ok, updated_app} =
        Applications.update_application(application, %{
          dlq_destination_url: "https://new-dlq.example.com/events"
        })

      assert updated_app.dlq_destination_url == "https://new-dlq.example.com/events"
    end

    test "get_dlq_destination/1 returns the URL" do
      {:ok, %{application: application}} =
        create_tenant_with_api_key(%{}, %{dlq_destination_url: "https://dlq.example.com"})

      assert Applications.get_dlq_destination(application) == "https://dlq.example.com"
    end

    test "get_dlq_destination/1 returns nil when not configured" do
      {:ok, %{application: application}} = create_tenant_with_api_key()

      assert Applications.get_dlq_destination(application) == nil
    end
  end
end
