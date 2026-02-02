defmodule RicqchetWeb.ActivityChannelTest do
  use RicqchetWeb.ChannelCase, async: false

  alias Ricqchet.ActivityEvents
  alias Ricqchet.Messages
  alias Ricqchet.Tenants

  setup do
    {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant #{System.unique_integer()}"})
    %{tenant: tenant}
  end

  describe "ActivityEvents broadcasting" do
    test "broadcasts message created event to tenant topic", %{tenant: tenant} do
      # Subscribe to the tenant's activity topic
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, "activity:tenant:#{tenant.id}")

      # Create a message which triggers the event
      {:ok, message} =
        Messages.create(tenant, %{
          destination_url: "https://example.com/webhook",
          payload: "test"
        })

      assert_receive {:activity_event, payload}
      assert payload.type == "message:created"
      assert payload.id == message.id
      assert payload.entity == "message"
    end

    test "broadcasts message delivered event", %{tenant: tenant} do
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, "activity:tenant:#{tenant.id}")

      # Create a message
      {:ok, message} =
        Messages.create(tenant, %{
          destination_url: "https://example.com/webhook",
          payload: "test"
        })

      # Clear the creation event
      assert_receive {:activity_event, _}

      # Manually set to dispatched
      {:ok, dispatched} =
        message
        |> Ecto.Changeset.change(status: "dispatched", dispatched_at: DateTime.utc_now())
        |> Ricqchet.Repo.update()

      # Mark as delivered
      {:ok, _delivered} = Messages.mark_delivered(dispatched, %{status: 200, body: "OK"})

      assert_receive {:activity_event, payload}
      assert payload.type == "message:delivered"
      assert payload.data.status_code == 200
    end

    test "broadcasts message failed event with retry", %{tenant: tenant} do
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, "activity:tenant:#{tenant.id}")

      # Create a message with multiple retries allowed
      {:ok, message} =
        Messages.create(tenant, %{
          destination_url: "https://example.com/webhook",
          payload: "test",
          max_retries: 3
        })

      # Clear the creation event
      assert_receive {:activity_event, _}

      # Manually set to dispatched
      {:ok, dispatched} =
        message
        |> Ecto.Changeset.change(status: "dispatched", dispatched_at: DateTime.utc_now())
        |> Ricqchet.Repo.update()

      # Mark as failed (will retry since max_retries > 1)
      {:ok, _failed} = Messages.mark_failed(dispatched, "Connection refused")

      assert_receive {:activity_event, payload}
      assert payload.type == "message:retrying"
      assert payload.data.error == "Connection refused"
    end

    test "broadcasts message permanently failed event", %{tenant: tenant} do
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, "activity:tenant:#{tenant.id}")

      # Create a message with only 1 retry allowed
      {:ok, message} =
        Messages.create(tenant, %{
          destination_url: "https://example.com/webhook",
          payload: "test",
          max_retries: 1
        })

      # Clear the creation event
      assert_receive {:activity_event, _}

      # Manually set to dispatched
      {:ok, dispatched} =
        message
        |> Ecto.Changeset.change(status: "dispatched", dispatched_at: DateTime.utc_now())
        |> Ricqchet.Repo.update()

      # Mark as failed (won't retry since attempts will equal max_retries)
      {:ok, _failed} = Messages.mark_failed(dispatched, "Connection refused")

      assert_receive {:activity_event, payload}
      assert payload.type == "message:failed"
    end

    test "includes timestamp in events", %{tenant: tenant} do
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, "activity:tenant:#{tenant.id}")

      {:ok, _message} =
        Messages.create(tenant, %{
          destination_url: "https://example.com/webhook",
          payload: "test"
        })

      assert_receive {:activity_event, payload}
      assert %DateTime{} = payload.timestamp
    end
  end

  describe "ActivityEvents direct broadcasting" do
    test "broadcasts to correct tenant topic", %{tenant: tenant} do
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, "activity:tenant:#{tenant.id}")

      message = %{
        id: Ecto.UUID.generate(),
        tenant_id: tenant.id,
        destination_url: "https://example.com/test",
        status: "pending",
        application_id: nil,
        payload_size_bytes: 100
      }

      ActivityEvents.message_created(message)

      assert_receive {:activity_event, payload}
      assert payload.type == "message:created"
      assert payload.id == message.id
    end

    test "does not broadcast to other tenants", %{tenant: tenant} do
      # Subscribe to a different tenant's topic
      other_tenant_id = Ecto.UUID.generate()
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, "activity:tenant:#{other_tenant_id}")

      message = %{
        id: Ecto.UUID.generate(),
        tenant_id: tenant.id,
        destination_url: "https://example.com/test",
        status: "pending",
        application_id: nil,
        payload_size_bytes: 100
      }

      ActivityEvents.message_created(message)

      refute_receive {:activity_event, _}, 100
    end
  end
end
