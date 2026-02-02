defmodule Ricqchet.Stats do
  @moduledoc """
  Context module for dashboard statistics and metrics.

  Provides aggregated statistics on messages, delivery performance,
  errors, and destinations scoped to a tenant.
  """

  import Ecto.Query

  alias Ricqchet.Messages.Message
  alias Ricqchet.Repo
  alias Ricqchet.Tenants.Tenant

  @default_period "1h"
  @default_limit 25
  @max_limit 100

  @type period :: String.t()
  @type opts :: keyword()

  @periods %{
    "5m" => 5 * 60,
    "1h" => 60 * 60,
    "4h" => 4 * 60 * 60,
    "1d" => 24 * 60 * 60,
    "1w" => 7 * 24 * 60 * 60
  }

  @doc """
  Returns message counts by status for a tenant.

  ## Options

    * `:period` - Time period: "5m", "1h", "4h", "1d", "1w" (default: "1h")

  ## Example

      iex> Stats.message_counts(tenant, period: "1h")
      %{
        period: "1h",
        counts: %{pending: 42, dispatched: 15, delivered: 1250, failed: 23},
        total: 1330
      }

  """
  @spec message_counts(Tenant.t(), opts()) :: map()
  def message_counts(%Tenant{id: tenant_id}, opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    since = period_to_datetime(period)

    raw_counts =
      Message
      |> where([m], m.tenant_id == ^tenant_id)
      |> where([m], m.inserted_at >= ^since)
      |> group_by([m], m.status)
      |> select([m], {m.status, count(m.id)})
      |> Repo.all()
      |> Map.new(fn {status, cnt} -> {String.to_atom(status), cnt} end)

    # Ensure all statuses are present
    counts = Map.merge(%{pending: 0, dispatched: 0, delivered: 0, failed: 0}, raw_counts)

    total =
      counts
      |> Map.values()
      |> Enum.sum()

    %{
      period: period,
      counts: counts,
      total: total
    }
  end

  @doc """
  Returns message size statistics for a tenant.

  ## Options

    * `:period` - Time period: "5m", "1h", "4h", "1d", "1w" (default: "1h")

  ## Example

      iex> Stats.message_sizes(tenant, period: "1h")
      %{
        period: "1h",
        message_count: 1250,
        total_bytes: 5242880,
        average_bytes: 4194,
        percentiles: %{p50: 2048, p95: 15360, p99: 32768}
      }

  """
  @spec message_sizes(Tenant.t(), opts()) :: map()
  def message_sizes(%Tenant{id: tenant_id}, opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    since = period_to_datetime(period)

    base_stats =
      Message
      |> where([m], m.tenant_id == ^tenant_id)
      |> where([m], m.inserted_at >= ^since)
      |> where([m], not is_nil(m.payload_size_bytes))
      |> select([m], %{
        count: count(m.id),
        total: coalesce(sum(m.payload_size_bytes), 0),
        avg: coalesce(fragment("AVG(?)", m.payload_size_bytes), 0)
      })
      |> Repo.one()

    percentiles = calculate_size_percentiles(tenant_id, since)

    %{
      period: period,
      message_count: base_stats.count,
      total_bytes: base_stats.total || 0,
      average_bytes: to_integer(base_stats.avg),
      percentiles: percentiles
    }
  end

  defp calculate_size_percentiles(tenant_id, since) do
    query = """
    SELECT
      COALESCE(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY payload_size_bytes), 0) AS p50,
      COALESCE(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY payload_size_bytes), 0) AS p95,
      COALESCE(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY payload_size_bytes), 0) AS p99
    FROM messages
    WHERE tenant_id = $1
      AND inserted_at >= $2
      AND payload_size_bytes IS NOT NULL
    """

    {:ok, uuid_binary} = Ecto.UUID.dump(tenant_id)

    case Repo.query(query, [uuid_binary, since]) do
      {:ok, %{rows: [[p50, p95, p99]]}} ->
        %{p50: to_integer(p50), p95: to_integer(p95), p99: to_integer(p99)}

      _ ->
        %{p50: 0, p95: 0, p99: 0}
    end
  end

  @doc """
  Returns delivery performance statistics for a tenant.

  ## Options

    * `:period` - Time period: "5m", "1h", "4h", "1d", "1w" (default: "1h")

  ## Example

      iex> Stats.delivery_performance(tenant, period: "1h")
      %{
        period: "1h",
        total_completed: 1273,
        success_rate: 98.19,
        retry_rate: 12.5,
        delivery_times: %{average_ms: 245, p95_ms: 890, p99_ms: 1450}
      }

  """
  @spec delivery_performance(Tenant.t(), opts()) :: map()
  def delivery_performance(%Tenant{id: tenant_id}, opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    since = period_to_datetime(period)

    stats =
      Message
      |> where([m], m.tenant_id == ^tenant_id)
      |> where([m], m.completed_at >= ^since)
      |> where([m], m.status in ["delivered", "failed"])
      |> select([m], %{
        total: count(m.id),
        delivered: fragment("COUNT(*) FILTER (WHERE status = 'delivered')"),
        failed: fragment("COUNT(*) FILTER (WHERE status = 'failed')"),
        retried: fragment("COUNT(*) FILTER (WHERE attempts > 1)")
      })
      |> Repo.one()

    delivery_times = calculate_delivery_time_percentiles(tenant_id, since)

    success_rate =
      if stats.total > 0,
        do: Float.round(stats.delivered / stats.total * 100, 2),
        else: 0.0

    retry_rate =
      if stats.total > 0,
        do: Float.round(stats.retried / stats.total * 100, 2),
        else: 0.0

    %{
      period: period,
      total_completed: stats.total,
      success_rate: success_rate,
      retry_rate: retry_rate,
      delivery_times: delivery_times
    }
  end

  defp calculate_delivery_time_percentiles(tenant_id, since) do
    query = """
    SELECT
      COALESCE(AVG(EXTRACT(EPOCH FROM (completed_at - dispatched_at)) * 1000), 0) AS avg_ms,
      COALESCE(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (completed_at - dispatched_at)) * 1000), 0) AS p95_ms,
      COALESCE(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (completed_at - dispatched_at)) * 1000), 0) AS p99_ms
    FROM messages
    WHERE tenant_id = $1
      AND completed_at >= $2
      AND status = 'delivered'
      AND dispatched_at IS NOT NULL
    """

    {:ok, uuid_binary} = Ecto.UUID.dump(tenant_id)

    case Repo.query(query, [uuid_binary, since]) do
      {:ok, %{rows: [[avg, p95, p99]]}} ->
        %{
          average_ms: to_integer(avg),
          p95_ms: to_integer(p95),
          p99_ms: to_integer(p99)
        }

      _ ->
        %{average_ms: 0, p95_ms: 0, p99_ms: 0}
    end
  end

  @doc """
  Returns error breakdown statistics for a tenant.

  ## Options

    * `:period` - Time period: "5m", "1h", "4h", "1d", "1w" (default: "1h")
    * `:limit` - Max number of failing destinations (default: 10)

  ## Example

      iex> Stats.error_breakdown(tenant, period: "1h")
      %{
        period: "1h",
        total_errors: 23,
        by_type: %{timeout: 12, connection_refused: 5, http_5xx: 4, http_4xx: 2},
        by_status_code: %{500 => 3, 502 => 1, 400 => 1, 401 => 1},
        top_failing_destinations: [%{url: "https://...", count: 8}]
      }

  """
  @spec error_breakdown(Tenant.t(), opts()) :: map()
  def error_breakdown(%Tenant{id: tenant_id}, opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    limit = min(Keyword.get(opts, :limit, 10), 50)
    since = period_to_datetime(period)

    failed_messages = fetch_failed_messages(tenant_id, since)

    %{
      period: period,
      total_errors: Enum.count(failed_messages),
      by_type: aggregate_by_error_type(failed_messages),
      by_status_code: aggregate_by_status_code(failed_messages),
      top_failing_destinations: aggregate_top_failing_destinations(failed_messages, limit)
    }
  end

  defp fetch_failed_messages(tenant_id, since) do
    Message
    |> where([m], m.tenant_id == ^tenant_id)
    |> where([m], m.completed_at >= ^since)
    |> where([m], m.status == "failed")
    |> select([m], %{
      last_error: m.last_error,
      last_response_status: m.last_response_status,
      destination_url: m.destination_url
    })
    |> Repo.all()
  end

  defp aggregate_by_error_type(messages) do
    messages
    |> Enum.map(&classify_error/1)
    |> Enum.frequencies()
  end

  defp aggregate_by_status_code(messages) do
    messages
    |> Enum.filter(&(&1.last_response_status != nil))
    |> Enum.frequencies_by(& &1.last_response_status)
  end

  defp aggregate_top_failing_destinations(messages, limit) do
    messages
    |> Enum.frequencies_by(& &1.destination_url)
    |> Enum.map(fn {url, count} -> %{url: url, count: count} end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(limit)
  end

  defp classify_error(%{last_response_status: status}) when is_integer(status) and status >= 500,
    do: :http_5xx

  defp classify_error(%{last_response_status: status}) when is_integer(status) and status >= 400,
    do: :http_4xx

  defp classify_error(%{last_error: error}) when is_binary(error) do
    classify_error_string(error)
  end

  defp classify_error(_), do: :other

  defp classify_error_string(error) do
    error_lower = String.downcase(error)

    cond do
      String.contains?(error_lower, "timeout") -> :timeout
      String.contains?(error_lower, "connection refused") -> :connection_refused
      String.contains?(error_lower, ["ssl", "tls", "certificate"]) -> :ssl_error
      String.contains?(error_lower, ["dns", "resolve"]) -> :dns_error
      true -> :other
    end
  end

  @doc """
  Returns per-destination metrics for a tenant.

  ## Options

    * `:period` - Time period: "5m", "1h", "4h", "1d", "1w" (default: "1h")
    * `:limit` - Max number of destinations (default: 10, max: 50)

  ## Example

      iex> Stats.destination_metrics(tenant, period: "1h", limit: 10)
      %{
        period: "1h",
        destinations: [
          %{url: "https://...", volume: 450, success_rate: 99.3, avg_response_time_ms: 180}
        ]
      }

  """
  @spec destination_metrics(Tenant.t(), opts()) :: map()
  def destination_metrics(%Tenant{id: tenant_id}, opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    limit = min(Keyword.get(opts, :limit, 10), 50)
    since = period_to_datetime(period)

    raw_destinations =
      Message
      |> where([m], m.tenant_id == ^tenant_id)
      |> where([m], m.completed_at >= ^since)
      |> where([m], m.status in ["delivered", "failed"])
      |> group_by([m], m.destination_url)
      |> order_by([m], desc: count(m.id))
      |> limit(^limit)
      |> select([m], %{
        url: m.destination_url,
        volume: count(m.id),
        delivered: fragment("COUNT(*) FILTER (WHERE status = 'delivered')"),
        avg_response_time_ms:
          fragment(
            "AVG(EXTRACT(EPOCH FROM (completed_at - dispatched_at)) * 1000) FILTER (WHERE status = 'delivered' AND dispatched_at IS NOT NULL)"
          )
      })
      |> Repo.all()

    destinations =
      Enum.map(raw_destinations, fn dest ->
        success_rate =
          if dest.volume > 0,
            do: Float.round(dest.delivered / dest.volume * 100, 2),
            else: 0.0

        %{
          url: dest.url,
          volume: dest.volume,
          success_rate: success_rate,
          avg_response_time_ms: to_integer(dest.avg_response_time_ms)
        }
      end)

    %{
      period: period,
      destinations: destinations
    }
  end

  @doc """
  Returns recent message activity for a tenant.

  ## Options

    * `:period` - Time period: "5m", "1h", "4h", "1d", "1w" (default: "1h")
    * `:limit` - Max messages to return (default: 25, max: 100)
    * `:status` - Filter by status (optional)
    * `:after_cursor` - Cursor for pagination (optional)

  ## Example

      iex> Stats.recent_activity(tenant, period: "1h", limit: 25)
      %{
        period: "1h",
        data: [%{id: "...", destination_url: "...", status: "delivered", ...}],
        meta: %{has_more: true, next_cursor: "..."}
      }

  """
  @spec recent_activity(Tenant.t(), opts()) :: map()
  def recent_activity(%Tenant{id: tenant_id}, opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    limit = min(Keyword.get(opts, :limit, @default_limit), @max_limit)
    status_filter = Keyword.get(opts, :status)
    after_cursor = Keyword.get(opts, :after_cursor)
    since = period_to_datetime(period)

    query =
      tenant_id
      |> build_activity_query(since, limit)
      |> apply_status_filter(status_filter)
      |> apply_cursor_filter(after_cursor)

    results = Repo.all(query)
    {data, has_more, next_cursor} = build_pagination_result(results, limit)

    %{
      period: period,
      data: data,
      meta: %{has_more: has_more, next_cursor: next_cursor}
    }
  end

  defp build_activity_query(tenant_id, since, limit) do
    Message
    |> where([m], m.tenant_id == ^tenant_id)
    |> where([m], m.inserted_at >= ^since)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^(limit + 1))
    |> select([m], %{
      id: m.id,
      destination_url: m.destination_url,
      status: m.status,
      attempts: m.attempts,
      last_error: m.last_error,
      last_response_status: m.last_response_status,
      payload_size_bytes: m.payload_size_bytes,
      application_id: m.application_id,
      created_at: m.inserted_at,
      completed_at: m.completed_at
    })
  end

  defp apply_status_filter(query, nil), do: query
  defp apply_status_filter(query, status), do: where(query, [m], m.status == ^status)

  defp apply_cursor_filter(query, nil), do: query

  defp apply_cursor_filter(query, cursor) do
    case decode_cursor(cursor) do
      {:ok, %{inserted_at: inserted_at, id: id}} ->
        where(
          query,
          [m],
          m.inserted_at < ^inserted_at or (m.inserted_at == ^inserted_at and m.id < ^id)
        )

      _ ->
        query
    end
  end

  defp build_pagination_result(results, limit) do
    result_count = Enum.count(results)
    has_more = results != [] and result_count > limit
    data = Enum.take(results, limit)
    next_cursor = build_next_cursor(data, has_more)
    {data, has_more, next_cursor}
  end

  defp build_next_cursor([], _has_more), do: nil
  defp build_next_cursor(_data, false), do: nil

  defp build_next_cursor(data, true) do
    last = List.last(data)
    encode_cursor(%{inserted_at: last.created_at, id: last.id})
  end

  # Cursor encoding/decoding for pagination
  defp encode_cursor(data) do
    data
    |> :erlang.term_to_binary()
    |> Base.url_encode64()
  end

  defp decode_cursor(cursor) do
    case Base.url_decode64(cursor) do
      {:ok, binary} ->
        try do
          {:ok, :erlang.binary_to_term(binary, [:safe])}
        rescue
          _ -> {:error, :invalid_cursor}
        end

      :error ->
        {:error, :invalid_cursor}
    end
  end

  # Convert period string to DateTime
  defp period_to_datetime(period) do
    seconds = Map.get(@periods, period, @periods[@default_period])
    DateTime.add(DateTime.utc_now(), -seconds, :second)
  end

  # Convert various number types to integer (handles Decimal from PostgreSQL)
  defp to_integer(nil), do: 0

  defp to_integer(%Decimal{} = d) do
    d
    |> Decimal.round()
    |> Decimal.to_integer()
  end

  defp to_integer(n) when is_float(n), do: round(n)
  defp to_integer(n) when is_integer(n), do: n
end
