defmodule Ricqchet.Dlq.NotificationWorkerTest do
  use Ricqchet.DataCase, async: true

  import ExUnit.CaptureLog

  alias Ricqchet.Batches
  alias Ricqchet.Dlq.NotificationWorker
  alias Ricqchet.Messages

  describe "perform/1 for messages" do
    test "returns :ok and logs when message not found" do
      job = %Oban.Job{
        args: %{
          "type" => "message",
          "entity_id" => Ecto.UUID.generate(),
          "destination_url" => "https://dlq.example.com/webhook"
        }
      }

      log =
        capture_log(fn ->
          assert :ok = NotificationWorker.perform(job)
        end)

      assert log =~ "not found"
      assert log =~ "discarding job"
    end

    test "returns :ok and logs when URL is not HTTPS" do
      {:ok, %{tenant: tenant, application: application}} =
        create_tenant_with_api_key(%{}, %{dlq_destination_url: "https://dlq.example.com/webhook"})

      {:ok, message} =
        Messages.create(tenant, %{destination_url: "https://example.com/api"}, application)

      job = %Oban.Job{
        args: %{
          "type" => "message",
          "entity_id" => message.id,
          "destination_url" => "http://insecure.example.com/webhook"
        }
      }

      log =
        capture_log(fn ->
          assert :ok = NotificationWorker.perform(job)
        end)

      assert log =~ "is not HTTPS"
      assert log =~ "discarding job"
    end

    test "returns :ok and logs when URL is invalid (blocked IP)" do
      {:ok, %{tenant: tenant, application: application}} =
        create_tenant_with_api_key(%{}, %{dlq_destination_url: "https://dlq.example.com/webhook"})

      {:ok, message} =
        Messages.create(tenant, %{destination_url: "https://example.com/api"}, application)

      # Use 10.x.x.x which is always blocked (127.x.x.x is allowed in test config for Bypass)
      job = %Oban.Job{
        args: %{
          "type" => "message",
          "entity_id" => message.id,
          "destination_url" => "https://10.0.0.1/webhook"
        }
      }

      log =
        capture_log(fn ->
          assert :ok = NotificationWorker.perform(job)
        end)

      assert log =~ "invalid"
      assert log =~ "discarding job"
    end
  end

  describe "perform/1 for batches" do
    test "returns :ok and logs when batch not found" do
      job = %Oban.Job{
        args: %{
          "type" => "batch",
          "entity_id" => Ecto.UUID.generate(),
          "destination_url" => "https://dlq.example.com/webhook"
        }
      }

      log =
        capture_log(fn ->
          assert :ok = NotificationWorker.perform(job)
        end)

      assert log =~ "not found"
      assert log =~ "discarding job"
    end

    test "returns :ok and logs when URL is not HTTPS" do
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

      job = %Oban.Job{
        args: %{
          "type" => "batch",
          "entity_id" => batch.id,
          "destination_url" => "http://insecure.example.com/webhook"
        }
      }

      log =
        capture_log(fn ->
          assert :ok = NotificationWorker.perform(job)
        end)

      assert log =~ "is not HTTPS"
      assert log =~ "discarding job"
    end
  end

  describe "job enqueuing" do
    test "enqueues job with correct args for message" do
      {:ok, %{tenant: tenant, application: application}} =
        create_tenant_with_api_key(%{}, %{dlq_destination_url: "https://dlq.example.com/webhook"})

      {:ok, message} =
        Messages.create(tenant, %{destination_url: "https://example.com/api"}, application)

      # Use manual mode to verify enqueuing without immediate execution
      Oban.Testing.with_testing_mode(:manual, fn ->
        Ricqchet.Dlq.maybe_notify_failure(message)

        assert_enqueued(
          worker: NotificationWorker,
          args: %{
            type: "message",
            entity_id: message.id,
            destination_url: "https://dlq.example.com/webhook"
          }
        )
      end)
    end

    test "enqueues job with correct args for batch" do
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

      # Use manual mode to verify enqueuing without immediate execution
      Oban.Testing.with_testing_mode(:manual, fn ->
        Ricqchet.Dlq.maybe_notify_failure(batch)

        assert_enqueued(
          worker: NotificationWorker,
          args: %{
            type: "batch",
            entity_id: batch.id,
            destination_url: "https://dlq.example.com/webhook"
          }
        )
      end)
    end

    test "does not enqueue job when application has no DLQ destination" do
      {:ok, %{tenant: tenant, application: application}} = create_tenant_with_api_key()

      {:ok, message} =
        Messages.create(tenant, %{destination_url: "https://example.com/api"}, application)

      Oban.Testing.with_testing_mode(:manual, fn ->
        Ricqchet.Dlq.maybe_notify_failure(message)
        refute_enqueued(worker: NotificationWorker)
      end)
    end

    test "does not enqueue job when DLQ destination is whitespace-only" do
      {:ok, %{tenant: tenant, application: application}} =
        create_tenant_with_api_key(%{}, %{dlq_destination_url: "   "})

      {:ok, message} =
        Messages.create(tenant, %{destination_url: "https://example.com/api"}, application)

      Oban.Testing.with_testing_mode(:manual, fn ->
        Ricqchet.Dlq.maybe_notify_failure(message)
        refute_enqueued(worker: NotificationWorker)
      end)
    end
  end
end
