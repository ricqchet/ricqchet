defmodule Ricqchet.Channels.ClientEventRateLimiter do
  @moduledoc """
  ETS-based rate limiter for client-to-client events.

  Uses a sliding window approach bucketed by second. Each key is
  `{application_id, subject_id, window_second}` with an atomic counter.
  Stale entries are cleaned up periodically.

  `subject_id` must be a **server-controlled, non-spoofable identifier** — callers
  pass the per-connection `connection_id` (not the client-supplied `user_id`) so a
  spoofed or rotated `user_id` cannot multiply a connection's event budget.
  """

  use GenServer

  @table __MODULE__
  @cleanup_interval_ms 5_000
  @default_limit 10

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if a client event is within the rate limit.

  `subject_id` is the rate-limit subject — a server-controlled identifier such as
  the connection id (never the spoofable, client-supplied `user_id`).

  Returns `:ok` if allowed, or `:rate_limited` if the limit is exceeded.
  The `limit` parameter defaults to #{@default_limit} events per second.
  """
  @spec check_rate(String.t(), String.t(), non_neg_integer()) :: :ok | :rate_limited
  def check_rate(application_id, subject_id, limit \\ @default_limit) do
    window = System.monotonic_time(:second)
    key = {application_id, subject_id, window}
    count = :ets.update_counter(@table, key, {2, 1}, {key, 0})

    if count <= limit, do: :ok, else: :rate_limited
  end

  ## Server Callbacks

  @impl GenServer
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set, {:write_concurrency, true}])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    current_window = System.monotonic_time(:second)

    # Delete entries older than 2 seconds
    match_spec = [
      {{{:_, :_, :"$1"}, :_}, [{:<, :"$1", current_window - 2}], [true]}
    ]

    :ets.select_delete(@table, match_spec)
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
