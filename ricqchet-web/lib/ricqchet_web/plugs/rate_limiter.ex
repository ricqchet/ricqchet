defmodule RicqchetWeb.Plugs.RateLimiter do
  @moduledoc """
  A simple ETS-based rate limiter plug.

  Limits requests per tenant based on API key to prevent abuse and DoS attacks.
  Uses a sliding window algorithm with configurable limits.

  ## Configuration

  Configure in your application config:

      config :ricqchet, RicqchetWeb.Plugs.RateLimiter,
        requests_per_second: 100,
        burst_size: 200

  ## Usage

  Add to your router pipeline:

      plug RicqchetWeb.Plugs.RateLimiter
  """

  import Plug.Conn

  alias RicqchetWeb.Plugs.RateLimiter.ETSTable

  @behaviour Plug

  @default_requests_per_second 100
  @default_burst_size 200
  @window_ms 1000

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_tenant_key(conn) do
      nil -> conn
      tenant_key -> check_rate_limit(conn, tenant_key)
    end
  end

  defp check_rate_limit(conn, tenant_key) do
    if allowed?(tenant_key) do
      conn
    else
      reject_request(conn)
    end
  end

  defp reject_request(conn) do
    conn
    |> put_resp_header("retry-after", "1")
    |> send_resp(
      429,
      Jason.encode!(%{error: "rate_limit_exceeded", message: "Too many requests"})
    )
    |> halt()
  end

  defp get_tenant_key(conn) do
    case conn.assigns[:current_tenant] do
      %{id: id} -> "tenant:#{id}"
      nil -> nil
    end
  end

  defp allowed?(key) do
    now = System.system_time(:millisecond)
    {requests_per_second, burst_size} = get_limits()
    table = ETSTable.table_name()

    case :ets.lookup(table, key) do
      [] ->
        init_window(table, key, now)

      [{^key, count, window_start}] ->
        check_window(table, key, count, window_start, now, requests_per_second, burst_size)
    end
  end

  defp init_window(table, key, now) do
    :ets.insert(table, {key, 1, now})
    true
  end

  defp check_window(table, key, count, window_start, now, requests_per_second, burst_size) do
    window_expired = now - window_start >= @window_ms

    cond do
      window_expired ->
        :ets.insert(table, {key, 1, now})
        true

      count < burst_size ->
        :ets.update_counter(table, key, {2, 1})
        true

      true ->
        check_rate(table, key, count, window_start, now, requests_per_second)
    end
  end

  defp check_rate(table, key, count, window_start, now, requests_per_second) do
    elapsed_ms = max(now - window_start, 1)
    rate = count * 1000 / elapsed_ms

    if rate < requests_per_second do
      :ets.update_counter(table, key, {2, 1})
      true
    else
      false
    end
  end

  defp get_limits do
    config = Application.get_env(:ricqchet, __MODULE__, [])
    requests_per_second = Keyword.get(config, :requests_per_second, @default_requests_per_second)
    burst_size = Keyword.get(config, :burst_size, @default_burst_size)
    {requests_per_second, burst_size}
  end

  @doc """
  Clears the rate limiter state. Useful for testing.
  """
  def reset do
    table = ETSTable.table_name()

    case :ets.whereis(table) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(table)
    end
  end
end
