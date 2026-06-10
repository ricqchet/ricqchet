defmodule Ricqchet.Channels.ConnectionTracker do
  @moduledoc """
  Tracks active channel WebSocket connections per application and enforces
  per-application connection limits.

  A connection is counted once per socket (transport) process, regardless of how
  many channels that socket multiplexes. The socket process is monitored, so the
  slot is released automatically when the socket disconnects — there is no
  separate disconnect call that could drift out of sync with the (per-join)
  channel lifecycle.

  Counts are kept in a public ETS table for fast concurrent reads (`get_count/1`).
  All mutations happen inside this GenServer, so reads are eventually consistent
  while increments, the limit check, and decrements stay race-free.
  """

  use GenServer

  @table __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a connection for `application_id` and monitors `pid` (the socket
  transport process) so the slot is released when it terminates.

  Returns `:ok`, or `:limit_reached` when `max_connections` is set and already met.
  """
  @spec track_connect(String.t(), non_neg_integer() | nil, pid()) :: :ok | :limit_reached
  def track_connect(application_id, max_connections, pid) do
    GenServer.call(__MODULE__, {:track_connect, application_id, max_connections, pid})
  end

  @doc """
  Returns the current connection count for an application.
  """
  @spec get_count(String.t()) :: non_neg_integer()
  def get_count(application_id) do
    case :ets.lookup(@table, application_id) do
      [{_, count}] -> count
      [] -> 0
    end
  end

  @impl GenServer
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set, {:write_concurrency, true}])
    {:ok, %{table: table, refs: %{}}}
  end

  @impl GenServer
  def handle_call({:track_connect, application_id, max_connections, pid}, _from, state) do
    if max_connections && get_count(application_id) >= max_connections do
      {:reply, :limit_reached, state}
    else
      ref = Process.monitor(pid)
      :ets.update_counter(@table, application_id, {2, 1}, {application_id, 0})
      {:reply, :ok, %{state | refs: Map.put(state.refs, ref, application_id)}}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.refs, ref) do
      {nil, _refs} ->
        {:noreply, state}

      {application_id, refs} ->
        release(application_id)
        {:noreply, %{state | refs: refs}}
    end
  end

  defp release(application_id) do
    case :ets.update_counter(@table, application_id, {2, -1, 0, 0}, {application_id, 0}) do
      0 -> :ets.delete_object(@table, {application_id, 0})
      _ -> :ok
    end

    :telemetry.execute(
      [:ricqchet, :channels, :connection, :closed],
      %{count: 1},
      %{application_id: application_id}
    )

    :ok
  end
end
