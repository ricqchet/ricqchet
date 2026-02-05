defmodule Ricqchet.FlowControl.ReconciliationWorker do
  @moduledoc """
  Periodic reconciliation of flow control state.

  Runs every minute to correct any drift from node crashes or bugs by
  reconciling `in_flight_count` with actual dispatched messages.

  Also cleans up stale state entries.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1

  require Logger

  alias Ricqchet.Repo

  @impl Oban.Worker
  def perform(_job) do
    reconcile_in_flight_counts()
    cleanup_stale_state()
    :ok
  end

  defp reconcile_in_flight_counts do
    # Update in_flight_count to match actual dispatched messages
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
    WHERE fcs.in_flight_count > 0
    """

    case Repo.query(query) do
      {:ok, %{num_rows: rows}} when rows > 0 ->
        Logger.info("Flow control reconciliation updated #{rows} entries")

      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Flow control reconciliation failed: #{inspect(reason)}")
    end
  end

  defp cleanup_stale_state do
    # Remove state entries that have been idle for over 24 hours
    # and have no in-flight messages
    cutoff = DateTime.add(DateTime.utc_now(), -24, :hour)

    query = """
    DELETE FROM flow_control_state
    WHERE in_flight_count = 0
      AND request_count = 0
      AND updated_at < $1
    """

    case Repo.query(query, [cutoff]) do
      {:ok, %{num_rows: rows}} when rows > 0 ->
        Logger.info("Flow control cleanup removed #{rows} stale entries")

      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Flow control cleanup failed: #{inspect(reason)}")
    end
  end
end
