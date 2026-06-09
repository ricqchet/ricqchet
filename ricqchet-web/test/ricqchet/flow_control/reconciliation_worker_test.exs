defmodule Ricqchet.FlowControl.ReconciliationWorkerTest do
  use Ricqchet.DataCase, async: false

  alias Ricqchet.FlowControl.Backends.Postgres
  alias Ricqchet.FlowControl.Destination
  alias Ricqchet.FlowControl.ReconciliationWorker
  alias Ricqchet.Repo
  alias Ricqchet.Tenants

  setup do
    {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant"})

    {:ok, destination} =
      %Destination{}
      |> Destination.create_changeset(tenant, %{
        destination_url: "https://example.com/webhook",
        parallelism: 5,
        rate_limit: 10
      })
      |> Repo.insert()

    %{destination: destination}
  end

  describe "start_link/1" do
    test "starts with custom interval" do
      {:ok, pid} = ReconciliationWorker.start_link(interval_ms: 60_000)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "returns :ignore when interval is false" do
      assert :ignore = ReconciliationWorker.init(interval_ms: false)
    end
  end

  describe "reconciliation" do
    test "corrects drifted in_flight_count", %{destination: destination} do
      # Acquire some slots to create state
      Postgres.acquire_slot(destination.id, 5, nil)
      Postgres.acquire_slot(destination.id, 5, nil)

      # Verify in_flight_count is 2
      assert get_state(destination.id).in_flight_count == 2

      # Reconciliation should correct it to 0 (no actual dispatched messages)
      {:ok, pid} = ReconciliationWorker.start_link(interval_ms: 50)

      # Wait for at least one reconciliation cycle
      Process.sleep(100)
      GenServer.stop(pid)

      assert get_state(destination.id).in_flight_count == 0
    end
  end

  defp get_state(destination_id) do
    "flow_control_state"
    |> where([s], s.destination_id == type(^destination_id, :binary_id))
    |> select([s], %{
      in_flight_count: s.in_flight_count,
      request_count: s.request_count
    })
    |> Repo.one!()
  end
end
