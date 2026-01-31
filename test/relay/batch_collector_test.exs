defmodule Relay.BatchCollectorTest do
  use Relay.DataCase, async: true

  alias Relay.BatchCollector
  alias Relay.Batches
  alias Relay.Tenants

  setup do
    {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant"})
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

    test "schedules batch for immediate dispatch when max_size reached", %{tenant: tenant} do
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

      batch_before = Batches.get(msg1.batch_id)
      # First message - batch should have scheduled_at in the future (timeout-based)
      assert batch_before.message_count == 1

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

      batch_after = Batches.get(msg1.batch_id)
      # Second message reaches max_size - scheduled_at should be set to now (immediate dispatch)
      assert batch_after.message_count == 2
      # scheduled_at should be <= now for immediate dispatch
      assert DateTime.compare(batch_after.scheduled_at, DateTime.utc_now()) in [:lt, :eq]
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
end
