defmodule Ricqchet.BatchesTest do
  use Ricqchet.DataCase, async: true

  alias Ricqchet.Batches
  alias Ricqchet.Messages
  alias Ricqchet.Tenants

  describe "find_or_create_collecting/4" do
    setup do
      {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant"})
      %{tenant: tenant}
    end

    test "creates a new batch when none exists", %{tenant: tenant} do
      assert {:ok, batch, :new} =
               Batches.find_or_create_collecting(
                 tenant,
                 "https://example.com/api",
                 "my-batch-key"
               )

      assert batch.batch_key == "my-batch-key"
      assert batch.destination_url == "https://example.com/api"
      assert batch.tenant_id == tenant.id
      assert batch.status == "collecting"
      assert batch.message_count == 0
    end

    test "returns existing batch when one exists", %{tenant: tenant} do
      {:ok, batch1, :new} =
        Batches.find_or_create_collecting(tenant, "https://example.com/api", "my-batch-key")

      {:ok, batch2, :existing} =
        Batches.find_or_create_collecting(tenant, "https://example.com/api", "my-batch-key")

      assert batch1.id == batch2.id
    end

    test "creates separate batches for different batch keys", %{tenant: tenant} do
      {:ok, batch1, :new} =
        Batches.find_or_create_collecting(tenant, "https://example.com/api", "key-1")

      {:ok, batch2, :new} =
        Batches.find_or_create_collecting(tenant, "https://example.com/api", "key-2")

      assert batch1.id != batch2.id
    end

    test "creates separate batches for different destinations", %{tenant: tenant} do
      {:ok, batch1, :new} =
        Batches.find_or_create_collecting(tenant, "https://example.com/api1", "same-key")

      {:ok, batch2, :new} =
        Batches.find_or_create_collecting(tenant, "https://example.com/api2", "same-key")

      assert batch1.id != batch2.id
    end

    test "respects custom max_size option", %{tenant: tenant} do
      {:ok, batch, :new} =
        Batches.find_or_create_collecting(
          tenant,
          "https://example.com/api",
          "my-batch-key",
          %{max_size: 20}
        )

      assert batch.max_size == 20
    end

    test "respects custom timeout_seconds option", %{tenant: tenant} do
      {:ok, batch, :new} =
        Batches.find_or_create_collecting(
          tenant,
          "https://example.com/api",
          "my-batch-key",
          %{timeout_seconds: 15}
        )

      assert batch.timeout_seconds == 15
    end
  end

  describe "increment_message_count/1" do
    setup do
      {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant"})

      {:ok, batch, :new} =
        Batches.find_or_create_collecting(
          tenant,
          "https://example.com/api",
          "my-batch-key",
          %{max_size: 3}
        )

      %{tenant: tenant, batch: batch}
    end

    test "increments message count and returns :collecting when not full", %{batch: batch} do
      {:ok, updated_batch, :collecting} = Batches.increment_message_count(batch)
      assert updated_batch.message_count == 1
    end

    test "returns :ready when batch reaches max_size", %{batch: batch} do
      {:ok, batch1, :collecting} = Batches.increment_message_count(batch)
      {:ok, batch2, :collecting} = Batches.increment_message_count(batch1)
      {:ok, updated_batch, :ready} = Batches.increment_message_count(batch2)

      assert updated_batch.message_count == 3
    end
  end

  describe "claim_next_ready/0" do
    setup do
      {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant"})
      %{tenant: tenant}
    end

    test "claims batch when size is reached", %{tenant: tenant} do
      {:ok, batch, :new} =
        Batches.find_or_create_collecting(
          tenant,
          "https://example.com/api",
          "my-batch-key",
          %{max_size: 2}
        )

      {:ok, batch1, :collecting} = Batches.increment_message_count(batch)
      {:ok, _batch2, :ready} = Batches.increment_message_count(batch1)

      {:ok, claimed_batch} = Batches.claim_next_ready()
      assert claimed_batch.id == batch.id
      assert claimed_batch.status == "dispatched"
    end

    test "claims batch when timeout is reached", %{tenant: tenant} do
      # Create batch with scheduled_at in the past
      {:ok, batch, :new} =
        Batches.find_or_create_collecting(
          tenant,
          "https://example.com/api",
          "my-batch-key",
          %{timeout_seconds: 0}
        )

      {:ok, _batch, :collecting} = Batches.increment_message_count(batch)

      {:ok, claimed_batch} = Batches.claim_next_ready()
      assert claimed_batch.id == batch.id
      assert claimed_batch.status == "dispatched"
    end

    test "returns error when no batches ready", %{tenant: tenant} do
      # Create batch that's not ready (future timeout, not full)
      {:ok, _batch, :new} =
        Batches.find_or_create_collecting(
          tenant,
          "https://example.com/api",
          "my-batch-key",
          %{timeout_seconds: 3600, max_size: 100}
        )

      assert {:error, :none_available} = Batches.claim_next_ready()
    end
  end

  describe "mark_delivered/2" do
    setup do
      {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant"})

      {:ok, batch, :new} =
        Batches.find_or_create_collecting(tenant, "https://example.com/api", "my-batch-key")

      # Create a message in the batch
      {:ok, _message} =
        Messages.create_for_batch(tenant, batch, %{
          destination_url: "https://example.com/api",
          payload: ~s({"test": true})
        })

      {:ok, updated_batch, _} = Batches.increment_message_count(batch)

      %{tenant: tenant, batch: updated_batch}
    end

    test "marks batch and messages as delivered", %{batch: batch} do
      response = %{status: 200, body: "OK"}

      {:ok, updated_batch} = Batches.mark_delivered(batch, response)

      assert updated_batch.status == "delivered"
      assert updated_batch.completed_at != nil
      assert updated_batch.last_response_status == 200
    end
  end

  describe "mark_failed/3" do
    setup do
      {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant"})

      {:ok, batch, :new} =
        Batches.find_or_create_collecting(
          tenant,
          "https://example.com/api",
          "my-batch-key",
          %{max_retries: 3}
        )

      %{tenant: tenant, batch: batch}
    end

    test "schedules retry when attempts remain", %{batch: batch} do
      {:ok, updated_batch} = Batches.mark_failed(batch, "Connection refused")

      assert updated_batch.status == "pending"
      assert updated_batch.attempts == 1
      assert updated_batch.last_error == "Connection refused"
      assert DateTime.compare(updated_batch.scheduled_at, DateTime.utc_now()) == :gt
    end

    test "marks as failed when max retries exceeded", %{batch: batch} do
      batch_with_attempts = %{batch | attempts: 2}
      {:ok, updated_batch} = Batches.mark_failed(batch_with_attempts, "Connection refused")

      assert updated_batch.status == "failed"
      assert updated_batch.attempts == 3
      assert updated_batch.completed_at != nil
    end
  end

  describe "get_batch_payloads/1" do
    setup do
      {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant"})

      {:ok, batch, :new} =
        Batches.find_or_create_collecting(tenant, "https://example.com/api", "my-batch-key")

      # Create messages in order
      {:ok, _msg1} =
        Messages.create_for_batch(tenant, batch, %{
          destination_url: "https://example.com/api",
          payload: ~s({"order": 1})
        })

      {:ok, _msg2} =
        Messages.create_for_batch(tenant, batch, %{
          destination_url: "https://example.com/api",
          payload: ~s({"order": 2})
        })

      {:ok, _msg3} =
        Messages.create_for_batch(tenant, batch, %{
          destination_url: "https://example.com/api",
          payload: ~s({"order": 3})
        })

      %{batch: batch}
    end

    test "returns payloads in insertion order", %{batch: batch} do
      payloads = Batches.get_batch_payloads(batch)

      assert length(payloads) == 3
      assert Enum.at(payloads, 0) == %{"order" => 1}
      assert Enum.at(payloads, 1) == %{"order" => 2}
      assert Enum.at(payloads, 2) == %{"order" => 3}
    end
  end
end
