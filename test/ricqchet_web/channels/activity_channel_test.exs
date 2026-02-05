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
      assert payload.id == message.id
      assert payload.status == "pending"
      assert payload.destination_url == "https://example.com/webhook"
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
      assert payload.status == "delivered"
      assert payload.last_response_status == 200
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
      assert payload.status == "retrying"
      assert payload.last_error == "Connection refused"
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
      assert payload.status == "failed"
    end

    test "includes created_at in events", %{tenant: tenant} do
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, "activity:tenant:#{tenant.id}")

      {:ok, _message} =
        Messages.create(tenant, %{
          destination_url: "https://example.com/webhook",
          payload: "test"
        })

      assert_receive {:activity_event, payload}
      assert %DateTime{} = payload.created_at
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
        attempts: 0,
        last_error: nil,
        last_response_status: nil,
        payload_size_bytes: 100,
        application_id: nil,
        inserted_at: DateTime.utc_now(),
        completed_at: nil
      }

      ActivityEvents.message_created(message)

      assert_receive {:activity_event, payload}
      assert payload.id == message.id
      assert payload.status == "pending"
      assert payload.destination_url == "https://example.com/test"
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
        attempts: 0,
        last_error: nil,
        last_response_status: nil,
        payload_size_bytes: 100,
        application_id: nil,
        inserted_at: DateTime.utc_now(),
        completed_at: nil
      }

      ActivityEvents.message_created(message)

      refute_receive {:activity_event, _}, 100
    end
  end
end
