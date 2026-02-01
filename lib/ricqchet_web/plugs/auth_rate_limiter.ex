defmodule RicqchetWeb.Plugs.AuthRateLimiter do
  @moduledoc """
  IP-based rate limiter for authentication endpoints.

  Limits requests per IP address for sensitive auth operations like
  password reset requests and email verification resends to prevent abuse.

  ## Configuration

  Configure in your application config:

      config :ricqchet, RicqchetWeb.Plugs.AuthRateLimiter,
        requests_per_minute: 5,
        window_ms: 60_000

  ## Usage

  Add to your router pipeline or specific routes:

      plug RicqchetWeb.Plugs.AuthRateLimiter
  """

  import Plug.Conn

  require Logger

  @behaviour Plug

  @table_name :ricqchet_auth_rate_limiter
  @default_requests_per_minute 5
  @default_window_ms 60_000

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    ensure_table_exists()
    ip_key = get_ip_key(conn)
    check_rate_limit(conn, ip_key)
  end

  defp check_rate_limit(conn, ip_key) do
    if allowed?(ip_key) do
      conn
    else
      reject_request(conn)
    end
  end

  defp reject_request(conn) do
    Logger.warning("Rate limit exceeded for auth endpoint from #{get_ip_string(conn)}")

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("retry-after", "60")
    |> send_resp(
      429,
      Jason.encode!(%{
        error: "rate_limit_exceeded",
        message: "Too many requests. Please try again later."
      })
    )
    |> halt()
  end

  defp ensure_table_exists do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:named_table, :public, :set, {:write_concurrency, true}])

      _ ->
        :ok
    end
  end

  defp get_ip_key(conn) do
    ip = get_client_ip(conn)
    ip_string = ip_to_string(ip)
    "auth:#{ip_string}"
  end

  defp get_ip_string(conn) do
    conn
    |> get_client_ip()
    |> ip_to_string()
  end

  defp ip_to_string(ip) when is_tuple(ip) do
    ip
    |> :inet.ntoa()
    |> to_string()
  end

  defp get_client_ip(conn) do
    # Check for X-Forwarded-For header (for reverse proxies)
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        parse_forwarded_ip(forwarded, conn.remote_ip)

      [] ->
        conn.remote_ip
    end
  end

  defp parse_forwarded_ip(forwarded, fallback_ip) do
    ip_string =
      forwarded
      |> String.split(",")
      |> List.first()
      |> String.trim()

    case parse_ip(ip_string) do
      {:ok, ip} -> ip
      _ -> fallback_ip
    end
  end

  defp parse_ip(ip_string) do
    ip_string
    |> String.to_charlist()
    |> :inet.parse_address()
  end

  defp allowed?(key) do
    now = System.system_time(:millisecond)
    {requests_per_minute, window_ms} = get_limits()

    case :ets.lookup(@table_name, key) do
      [] ->
        init_window(key, now)

      [{^key, count, window_start}] ->
        check_window(key, count, window_start, now, requests_per_minute, window_ms)
    end
  end

  defp init_window(key, now) do
    :ets.insert(@table_name, {key, 1, now})
    true
  end

  defp check_window(key, count, window_start, now, requests_per_minute, window_ms) do
    window_expired = now - window_start >= window_ms

    cond do
      window_expired ->
        :ets.insert(@table_name, {key, 1, now})
        true

      count < requests_per_minute ->
        :ets.update_counter(@table_name, key, {2, 1})
        true

      true ->
        false
    end
  end

  defp get_limits do
    config = Application.get_env(:ricqchet, __MODULE__, [])
    requests_per_minute = Keyword.get(config, :requests_per_minute, @default_requests_per_minute)
    window_ms = Keyword.get(config, :window_ms, @default_window_ms)
    {requests_per_minute, window_ms}
  end

  @doc """
  Clears the rate limiter state. Useful for testing.
  """
  def reset do
    case :ets.whereis(@table_name) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(@table_name)
    end
  end
end
