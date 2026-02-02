defmodule Ricqchet.StatsTest do
  use Ricqchet.DataCase, async: false

  alias Ricqchet.Messages
  alias Ricqchet.Stats
  alias Ricqchet.Tenants

  setup do
    {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant #{System.unique_integer()}"})
    %{tenant: tenant}
  end

  describe "message_counts/2" do
    test "returns counts by status", %{tenant: tenant} do
      # Create messages with different statuses
      {:ok, _} = create_message(tenant, %{})
      {:ok, msg} = create_message(tenant, %{})

      msg
      |> Ecto.Changeset.change(status: "delivered", completed_at: DateTime.utc_now())
      |> Repo.update!()

      result = Stats.message_counts(tenant)

      assert result.period == "1h"
      assert result.counts.pending >= 1
      assert result.counts.delivered >= 1
      assert result.total >= 2
    end

    test "filters by time period", %{tenant: tenant} do
      {:ok, _} = create_message(tenant, %{})

      result = Stats.message_counts(tenant, period: "5m")

      assert result.period == "5m"
      assert result.total >= 0
    end

    test "returns zero counts when no messages", %{tenant: tenant} do
      result = Stats.message_counts(tenant)

      assert result.counts == %{pending: 0, dispatched: 0, delivered: 0, failed: 0}
      assert result.total == 0
    end
  end

  describe "message_sizes/2" do
    test "returns size statistics", %{tenant: tenant} do
      {:ok, _} = create_message(tenant, %{payload: String.duplicate("x", 100)})
      {:ok, _} = create_message(tenant, %{payload: String.duplicate("y", 200)})

      result = Stats.message_sizes(tenant)

      assert result.period == "1h"
      assert result.message_count >= 2
      assert result.total_bytes >= 300
      assert result.average_bytes > 0
      assert is_map(result.percentiles)
    end
  end

  describe "delivery_performance/2" do
    test "calculates success and retry rates", %{tenant: tenant} do
      # Create delivered message
      {:ok, msg1} = create_message(tenant, %{})

      msg1
      |> Ecto.Changeset.change(
        status: "delivered",
        completed_at: DateTime.utc_now(),
        dispatched_at: DateTime.add(DateTime.utc_now(), -1, :second),
        attempts: 1
      )
      |> Repo.update!()

      # Create failed message
      {:ok, msg2} = create_message(tenant, %{max_retries: 1})

      msg2
      |> Ecto.Changeset.change(
        status: "failed",
        completed_at: DateTime.utc_now(),
        dispatched_at: DateTime.add(DateTime.utc_now(), -1, :second),
        attempts: 1
      )
      |> Repo.update!()

      result = Stats.delivery_performance(tenant)

      assert result.period == "1h"
      assert result.total_completed >= 2
      assert is_number(result.success_rate)
      assert is_number(result.retry_rate)
    end
  end

  describe "error_breakdown/2" do
    test "categorizes errors by type", %{tenant: tenant} do
      {:ok, msg} = create_message(tenant, %{max_retries: 1})

      msg
      |> Ecto.Changeset.change(
        status: "failed",
        completed_at: DateTime.utc_now(),
        last_error: "Connection refused"
      )
      |> Repo.update!()

      result = Stats.error_breakdown(tenant)

      assert result.period == "1h"
      assert result.total_errors >= 1
      assert is_map(result.by_type)
    end
  end

  describe "destination_metrics/2" do
    test "groups metrics by destination", %{tenant: tenant} do
      url = "https://example.com/test"

      {:ok, msg1} = create_message(tenant, %{destination_url: url})

      msg1
      |> Ecto.Changeset.change(
        status: "delivered",
        completed_at: DateTime.utc_now(),
        dispatched_at: DateTime.add(DateTime.utc_now(), -1, :second)
      )
      |> Repo.update!()

      {:ok, msg2} = create_message(tenant, %{destination_url: url})

      msg2
      |> Ecto.Changeset.change(
        status: "delivered",
        completed_at: DateTime.utc_now(),
        dispatched_at: DateTime.add(DateTime.utc_now(), -1, :second)
      )
      |> Repo.update!()

      result = Stats.destination_metrics(tenant)

      assert result.period == "1h"
      assert is_list(result.destinations)

      if result.destinations != [] do
        dest = Enum.find(result.destinations, &(&1.url == url))
        assert dest.volume >= 2
        assert dest.success_rate == 100.0
      end
    end
  end

  describe "recent_activity/2" do
    test "returns paginated recent messages", %{tenant: tenant} do
      {:ok, _} = create_message(tenant, %{})
      {:ok, _} = create_message(tenant, %{})

      result = Stats.recent_activity(tenant, limit: 10)

      assert result.period == "1h"
      assert is_list(result.data)
      assert length(result.data) >= 2
      assert is_map(result.meta)
    end

    test "supports status filtering", %{tenant: tenant} do
      {:ok, _} = create_message(tenant, %{})
      {:ok, msg} = create_message(tenant, %{})

      msg
      |> Ecto.Changeset.change(status: "delivered", completed_at: DateTime.utc_now())
      |> Repo.update!()

      result = Stats.recent_activity(tenant, status: "pending")

      statuses = Enum.map(result.data, & &1.status)
      assert Enum.all?(statuses, &(&1 == "pending"))
    end

    test "supports cursor-based pagination", %{tenant: tenant} do
      for _i <- 1..5 do
        {:ok, _} = create_message(tenant, %{})
      end

      result1 = Stats.recent_activity(tenant, limit: 2)
      assert length(result1.data) == 2
      assert result1.meta.has_more == true
      assert result1.meta.next_cursor != nil

      result2 = Stats.recent_activity(tenant, limit: 2, after_cursor: result1.meta.next_cursor)
      assert length(result2.data) == 2

      # Verify different messages
      ids1 = Enum.map(result1.data, & &1.id)
      ids2 = Enum.map(result2.data, & &1.id)
      assert Enum.all?(ids2, &(&1 not in ids1))
    end
  end

  # Helper to create test messages
  defp create_message(tenant, attrs) do
    base_attrs = %{
      destination_url:
        attrs[:destination_url] || "https://example.com/webhook#{System.unique_integer()}",
      payload: attrs[:payload] || "test payload",
      max_retries: attrs[:max_retries] || 3
    }

    Messages.create(tenant, base_attrs)
  end
end
