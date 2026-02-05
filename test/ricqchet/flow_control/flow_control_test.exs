defmodule Ricqchet.FlowControlTest do
  use Ricqchet.DataCase, async: false

  alias Ricqchet.FlowControl
  alias Ricqchet.FlowControl.Destination
  alias Ricqchet.FlowControl.SettingsCache
  alias Ricqchet.Messages.Message
  alias Ricqchet.Repo
  alias Ricqchet.Tenants

  setup do
    {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant"})

    {:ok, destination} =
      %Destination{}
      |> Destination.create_changeset(tenant, %{
        destination_url: "https://example.com/webhook",
        parallelism: 3,
        rate_limit: 10
      })
      |> Repo.insert()

    # Ensure cache is clean
    SettingsCache.invalidate_all()

    %{destination: destination}
  end

  describe "acquire_slot/1" do
    test "returns ok for message with no destination_id" do
      message = %Message{destination_id: nil}
      assert :ok = FlowControl.acquire_slot(message)
    end

    test "returns ok when under limits", %{destination: destination} do
      message = %Message{destination_id: destination.id}
      assert :ok = FlowControl.acquire_slot(message)
    end

    test "returns delay when parallelism limit reached", %{destination: destination} do
      message = %Message{destination_id: destination.id}

      for _ <- 1..3 do
        assert :ok = FlowControl.acquire_slot(message)
      end

      assert {:delay, delay} = FlowControl.acquire_slot(message)
      assert delay > 0
    end

    test "returns ok for unknown destination" do
      message = %Message{destination_id: Ecto.UUID.generate()}
      assert :ok = FlowControl.acquire_slot(message)
    end
  end

  describe "release_slot/1" do
    test "returns ok for message with no destination_id" do
      message = %Message{destination_id: nil}
      assert :ok = FlowControl.release_slot(message)
    end

    test "releases a parallelism slot", %{destination: destination} do
      message = %Message{destination_id: destination.id}

      for _ <- 1..3 do
        assert :ok = FlowControl.acquire_slot(message)
      end

      assert {:delay, _} = FlowControl.acquire_slot(message)

      assert :ok = FlowControl.release_slot(message)
      assert :ok = FlowControl.acquire_slot(message)
    end
  end

  describe "get_settings/1" do
    test "loads settings from database", %{destination: destination} do
      assert {:ok, {3, 10}} = FlowControl.get_settings(destination.id)
    end

    test "caches settings on subsequent calls", %{destination: destination} do
      assert {:ok, {3, 10}} = FlowControl.get_settings(destination.id)
      # Second call should hit cache
      assert {:ok, {3, 10}} = FlowControl.get_settings(destination.id)
    end

    test "returns error for unknown destination" do
      assert :error = FlowControl.get_settings(Ecto.UUID.generate())
    end
  end
end
