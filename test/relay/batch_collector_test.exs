defmodule Relay.BatchCollectorTest do
  use Relay.DataCase, async: false

  alias Relay.BatchCollector
  alias Relay.Batches
  alias Relay.Tenants

  setup do
    {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant"})

    # Start BatchCollector for this test
    {:ok, pid} = BatchCollector.start_link([])

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    %{tenant: tenant}
  end

  describe "add_message/5" do
    test "creates batch and message when adding first message", %{tenant: tenant} do
      {:ok, message} =
        BatchCollector.add_message(
          tenant,
          "order-events",
          "https://example.com/api",
          %{
            destination_url: "https://example.com/api",
            payload: ~s({"event": "order.created"})
          }
        )

      assert message.id != nil
      assert message.batch_id != nil
      assert message.payload == ~s({"event": "order.created"})

      # Verify batch was created
      batch = Batches.get(message.batch_id)
      assert batch.batch_key == "order-events"
      assert batch.status == "collecting"
      assert batch.message_count == 1
    end

    test "groups messages with same batch key", %{tenant: tenant} do
      {:ok, msg1} =
        BatchCollector.add_message(
          tenant,
          "order-events",
          "https://example.com/api",
          %{
            destination_url: "https://example.com/api",
            payload: ~s({"event": "first"})
          }
        )

      {:ok, msg2} =
        BatchCollector.add_message(
          tenant,
          "order-events",
          "https://example.com/api",
          %{
            destination_url: "https://example.com/api",
            payload: ~s({"event": "second"})
          }
        )

      # Both messages should be in the same batch
      assert msg1.batch_id == msg2.batch_id

      batch = Batches.get(msg1.batch_id)
      assert batch.message_count == 2
    end

    test "creates separate batches for different batch keys", %{tenant: tenant} do
      {:ok, msg1} =
        BatchCollector.add_message(
          tenant,
          "order-events",
          "https://example.com/api",
          %{
            destination_url: "https://example.com/api",
            payload: ~s({"event": "order"})
          }
        )

      {:ok, msg2} =
        BatchCollector.add_message(
          tenant,
          "user-events",
          "https://example.com/api",
          %{
            destination_url: "https://example.com/api",
            payload: ~s({"event": "user"})
          }
        )

      assert msg1.batch_id != msg2.batch_id
    end

    test "dispatches batch when max_size reached", %{tenant: tenant} do
      batch_opts = %{max_size: 2}

      {:ok, msg1} =
        BatchCollector.add_message(
          tenant,
          "order-events",
          "https://example.com/api",
          %{
            destination_url: "https://example.com/api",
            payload: ~s({"event": "first"})
          },
          batch_opts
        )

      {:ok, _msg2} =
        BatchCollector.add_message(
          tenant,
          "order-events",
          "https://example.com/api",
          %{
            destination_url: "https://example.com/api",
            payload: ~s({"event": "second"})
          },
          batch_opts
        )

      # Give Oban a moment to process (inline mode)
      Process.sleep(50)

      # Batch should have been dispatched (may be back to collecting after failed delivery)
      batch = Batches.get(msg1.batch_id)
      # After dispatch, if delivery fails it goes back to "collecting" for retry
      # So we check that at least one attempt was made
      assert batch.attempts >= 1 or batch.status in ["dispatched", "delivered", "failed"]
    end

    test "respects custom batch options", %{tenant: tenant} do
      batch_opts = %{max_size: 50, timeout_seconds: 30}

      {:ok, message} =
        BatchCollector.add_message(
          tenant,
          "order-events",
          "https://example.com/api",
          %{
            destination_url: "https://example.com/api",
            payload: ~s({"event": "test"})
          },
          batch_opts
        )

      batch = Batches.get(message.batch_id)
      assert batch.max_size == 50
      assert batch.timeout_seconds == 30
    end
  end

  describe "timeout behavior" do
    test "dispatches batch after timeout", %{tenant: tenant} do
      # Use a very short timeout for testing
      batch_opts = %{timeout_seconds: 1, max_size: 100}

      {:ok, message} =
        BatchCollector.add_message(
          tenant,
          "order-events",
          "https://example.com/api",
          %{
            destination_url: "https://example.com/api",
            payload: ~s({"event": "test"})
          },
          batch_opts
        )

      # Wait for timeout to fire (plus some buffer)
      Process.sleep(1500)

      # Batch should have been dispatched (may be back to collecting after failed delivery)
      batch = Batches.get(message.batch_id)
      # After dispatch, if delivery fails it goes back to "collecting" for retry
      # So we check that at least one attempt was made
      assert batch.attempts >= 1 or batch.status in ["dispatched", "delivered", "failed"]
    end
  end
end
