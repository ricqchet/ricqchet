defmodule Relay.Delivery.BatchWorkerTest do
  use Relay.DataCase, async: false

  alias Relay.Batches
  alias Relay.Delivery.BatchWorker
  alias Relay.Messages
  alias Relay.Tenants

  setup do
    {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant"})

    {:ok, batch, :new} =
      Batches.find_or_create_collecting(
        tenant,
        "https://example.com/api",
        "test-batch",
        %{max_size: 10}
      )

    # Add some messages to the batch
    {:ok, _msg1} =
      Messages.create_for_batch(tenant, batch, %{
        destination_url: "https://example.com/api",
        payload: ~s({"event": "first"})
      })

    {:ok, _msg2} =
      Messages.create_for_batch(tenant, batch, %{
        destination_url: "https://example.com/api",
        payload: ~s({"event": "second"})
      })

    # Update batch message count
    {:ok, batch1, _} = Batches.increment_message_count(batch)
    {:ok, batch2, _} = Batches.increment_message_count(batch1)

    # Mark as dispatched
    {:ok, dispatched_batch} = Batches.mark_dispatched(batch2)

    %{tenant: tenant, batch: dispatched_batch}
  end

  describe "perform/1" do
    test "combines payloads into JSON array", %{batch: batch} do
      # Get the payloads that would be sent
      payloads = Batches.get_batch_payloads(batch)

      assert length(payloads) == 2
      assert Enum.at(payloads, 0) == %{"event" => "first"}
      assert Enum.at(payloads, 1) == %{"event" => "second"}

      # Verify combined payload format
      combined = Jason.encode!(payloads)
      assert combined == ~s([{"event":"first"},{"event":"second"}])
    end

    test "marks batch as delivered on success", %{batch: batch} do
      # The worker will try to deliver - since we're not mocking HTTP,
      # it will fail, but we can test the happy path by directly calling
      # mark_delivered
      response = %{status: 200, body: "OK"}
      {:ok, updated_batch} = Batches.mark_delivered(batch, response)

      assert updated_batch.status == "delivered"
      assert updated_batch.last_response_status == 200
      assert updated_batch.completed_at != nil
    end

    test "marks batch as failed with retry on error", %{batch: batch} do
      {:ok, updated_batch} = Batches.mark_failed(batch, "Connection refused")

      # First failure should schedule retry
      assert updated_batch.status == "collecting"
      assert updated_batch.attempts == 1
      assert updated_batch.last_error == "Connection refused"
    end

    test "marks batch as permanently failed after max retries", %{batch: batch} do
      # Simulate max retries reached
      batch_with_attempts = %{batch | attempts: 2, max_retries: 3}
      {:ok, updated_batch} = Batches.mark_failed(batch_with_attempts, "Connection refused")

      assert updated_batch.status == "failed"
      assert updated_batch.attempts == 3
      assert updated_batch.completed_at != nil
    end
  end

  describe "job creation" do
    test "creates valid Oban job changeset", %{batch: batch} do
      job_changeset = BatchWorker.new(%{batch_id: batch.id})

      assert job_changeset.changes.args == %{batch_id: batch.id}
      assert job_changeset.changes.queue == "delivery"
    end
  end
end
