defmodule Ricqchet.FlowControl.ReconciliationWorker do
  @moduledoc """
  Periodic reconciliation of flow control state.

  Runs on a configurable interval (default 10 seconds) to correct any
  drift from node crashes or bugs by reconciling `in_flight_count` with
  actual dispatched messages.

  Also cleans up stale state entries.

  ## Configuration

      config :ricqchet,
        flow_control_reconciliation_interval_ms: 10_000

  Set to `false` to disable reconciliation (useful in tests).
  """

  use GenServer

  require Logger

  alias Ricqchet.Repo

  @default_interval_ms 10_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, configured_interval())

    if interval do
      schedule_reconciliation(interval)
      {:ok, %{interval: interval}}
    else
      :ignore
    end
  end

  @impl GenServer
  def handle_info(:reconcile, state) do
    {duration_us, rows_corrected} =
      :timer.tc(fn ->
        rows_corrected = reconcile_in_flight_counts()
        cleanup_stale_state()
        rows_corrected
      end)

    :telemetry.execute(
      [:ricqchet, :flow_control, :reconciliation],
      %{duration: duration_us},
      %{rows_corrected: rows_corrected}
    )

    schedule_reconciliation(state.interval)
    {:noreply, state}
  end

  defp schedule_reconciliation(interval_ms) do
    Process.send_after(self(), :reconcile, interval_ms)
  end

  defp configured_interval do
    Application.get_env(:ricqchet, :flow_control_reconciliation_interval_ms, @default_interval_ms)
  end

  defp reconcile_in_flight_counts do
    query = """
    UPDATE flow_control_state fcs
    SET in_flight_count = COALESCE(
      (SELECT COUNT(*)
       FROM messages m
       WHERE m.destination_id = fcs.destination_id
         AND m.status = 'dispatched'),
      0
    ),
    updated_at = NOW()
    WHERE fcs.in_flight_count != COALESCE(
      (SELECT COUNT(*)
       FROM messages m
       WHERE m.destination_id = fcs.destination_id
         AND m.status = 'dispatched'),
      0
    )
    """

    case Repo.query(query) do
      {:ok, %{num_rows: rows}} when rows > 0 ->
        Logger.info("Flow control reconciliation corrected entries",
          rows_corrected: rows
        )

        rows

      {:ok, _} ->
        0

      {:error, reason} ->
        Logger.warning("Flow control reconciliation failed",
          error: inspect(reason)
        )

        0
    end
  end

  defp cleanup_stale_state do
    cutoff = DateTime.add(DateTime.utc_now(), -24, :hour)

    query = """
    DELETE FROM flow_control_state
    WHERE in_flight_count = 0
      AND request_count = 0
      AND updated_at < $1
    """

    case Repo.query(query, [cutoff]) do
      {:ok, %{num_rows: rows}} when rows > 0 ->
        Logger.info("Flow control cleanup removed stale entries",
          rows_removed: rows
        )

      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Flow control cleanup failed",
          error: inspect(reason)
        )
    end
  end
end
