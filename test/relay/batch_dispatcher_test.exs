defmodule Relay.BatchDispatcherTest do
  use Relay.DataCase, async: false

  alias Relay.BatchDispatcher
  alias Relay.Batches
  alias Relay.Messages
  alias Relay.Tenants

  setup do
    {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant"})
    %{tenant: tenant}
  end

  describe "dispatch_ready_batches/0" do
    test "dispatches batch when size is reached", %{tenant: tenant} do
      # Create a batch that's ready (at max size)
      {:ok, batch, :new} =
        Batches.find_or_create_collecting(
          tenant,
          "https://example.com/api",
          "test-batch",
          %{max_size: 2}
        )

      # Add messages to reach max_size
      {:ok, _msg1} =
        Messages.create_for_batch(tenant, batch, %{
          destination_url: "https://example.com/api",
          payload: ~s({"event": "first"})
        })

      {:ok, batch1, :collecting} = Batches.increment_message_count(batch)

      {:ok, _msg2} =
        Messages.create_for_batch(tenant, batch, %{
          destination_url: "https://example.com/api",
          payload: ~s({"event": "second"})
        })

      {:ok, _batch2, :ready} = Batches.increment_message_count(batch1)

      # Schedule for immediate dispatch
      {:ok, _} = Batches.schedule_for_immediate_dispatch(batch)

      # Claim and dispatch
      {:ok, claimed_batch} = Batches.claim_next_ready()

      assert claimed_batch.id == batch.id
      assert claimed_batch.status == "dispatched"
    end

    test "dispatches batch when timeout is reached", %{tenant: tenant} do
      # Create batch with scheduled_at in the past (0 second timeout)
      {:ok, batch, :new} =
        Batches.find_or_create_collecting(
          tenant,
          "https://example.com/api",
          "test-batch",
          %{timeout_seconds: 0}
        )

      # Add one message
      {:ok, _msg} =
        Messages.create_for_batch(tenant, batch, %{
          destination_url: "https://example.com/api",
          payload: ~s({"event": "test"})
        })

      {:ok, _batch, :collecting} = Batches.increment_message_count(batch)

      # Claim should work since scheduled_at is now <= current time
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
          "test-batch",
          %{timeout_seconds: 3600, max_size: 100}
        )

      assert {:error, :none_available} = Batches.claim_next_ready()
    end
  end

  describe "GenServer behavior" do
    test "starts and polls for batches" do
      # Start the dispatcher
      {:ok, pid} = BatchDispatcher.start_link([])
      assert Process.alive?(pid)

      # Clean up
      GenServer.stop(pid)
    end
  end
end
