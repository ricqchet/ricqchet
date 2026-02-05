defmodule Ricqchet.FlowControl.Backends.PostgresTest do
  use Ricqchet.DataCase, async: false

  alias Ricqchet.FlowControl.Backends.Postgres
  alias Ricqchet.FlowControl.Destination
  alias Ricqchet.Repo
  alias Ricqchet.Tenants

  setup do
    {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant"})

    {:ok, destination} =
      %Destination{}
      |> Destination.create_changeset(tenant, %{
        destination_url: "https://example.com/webhook",
        parallelism: 2,
        rate_limit: 5
      })
      |> Repo.insert()

    %{destination: destination}
  end

  describe "acquire_slot/3 with parallelism only" do
    test "allows slots under the limit", %{destination: destination} do
      assert :ok = Postgres.acquire_slot(destination.id, 2, nil)
    end

    test "allows multiple slots under the limit", %{destination: destination} do
      assert :ok = Postgres.acquire_slot(destination.id, 2, nil)
      assert :ok = Postgres.acquire_slot(destination.id, 2, nil)
    end

    test "returns delay when parallelism limit reached", %{destination: destination} do
      assert :ok = Postgres.acquire_slot(destination.id, 2, nil)
      assert :ok = Postgres.acquire_slot(destination.id, 2, nil)
      assert {:delay, delay} = Postgres.acquire_slot(destination.id, 2, nil)
      assert delay > 0
    end
  end

  describe "acquire_slot/3 with rate limit only" do
    test "allows requests under the limit", %{destination: destination} do
      assert :ok = Postgres.acquire_slot(destination.id, nil, 5)
    end

    test "allows multiple requests under the limit", %{destination: destination} do
      for _ <- 1..5 do
        assert :ok = Postgres.acquire_slot(destination.id, nil, 5)
      end
    end

    test "returns delay when rate limit reached", %{destination: destination} do
      for _ <- 1..5 do
        assert :ok = Postgres.acquire_slot(destination.id, nil, 5)
      end

      assert {:delay, delay} = Postgres.acquire_slot(destination.id, nil, 5)
      assert delay > 0
    end
  end

  describe "acquire_slot/3 with both limits" do
    test "allows when both limits are under capacity", %{destination: destination} do
      assert :ok = Postgres.acquire_slot(destination.id, 5, 10)
    end

    test "returns delay when parallelism is exceeded first", %{destination: destination} do
      assert :ok = Postgres.acquire_slot(destination.id, 1, 10)
      assert {:delay, _} = Postgres.acquire_slot(destination.id, 1, 10)
    end

    test "returns delay when rate limit is exceeded first", %{destination: destination} do
      assert :ok = Postgres.acquire_slot(destination.id, 10, 1)
      assert {:delay, _} = Postgres.acquire_slot(destination.id, 10, 1)
    end
  end

  describe "acquire_slot/3 with no limits" do
    test "always returns ok", %{destination: destination} do
      for _ <- 1..20 do
        assert :ok = Postgres.acquire_slot(destination.id, nil, nil)
      end
    end
  end

  describe "release_slot/1" do
    test "decrements the in-flight count", %{destination: destination} do
      assert :ok = Postgres.acquire_slot(destination.id, 2, nil)
      assert :ok = Postgres.acquire_slot(destination.id, 2, nil)
      assert {:delay, _} = Postgres.acquire_slot(destination.id, 2, nil)

      assert :ok = Postgres.release_slot(destination.id)
      assert :ok = Postgres.acquire_slot(destination.id, 2, nil)
    end

    test "does not go below zero", %{destination: destination} do
      assert :ok = Postgres.acquire_slot(destination.id, 2, nil)
      assert :ok = Postgres.release_slot(destination.id)
      assert :ok = Postgres.release_slot(destination.id)
      assert :ok = Postgres.release_slot(destination.id)

      # Should still work fine
      assert :ok = Postgres.acquire_slot(destination.id, 2, nil)
    end

    test "returns ok for unknown destination" do
      assert :ok = Postgres.release_slot(Ecto.UUID.generate())
    end
  end
end
