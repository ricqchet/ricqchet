defmodule Ricqchet.Channels.ConnectionTracker do
  @moduledoc """
  ETS-based connection counter for channel WebSocket connections.

  Tracks the number of active connections per application using atomic
  ETS counter operations. Used to enforce connection limits.
  """

  use GenServer

  @table __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Tracks a new connection. Returns `:ok` or `:limit_reached`.
  """
  @spec track_connect(String.t(), non_neg_integer() | nil) :: :ok | :limit_reached
  def track_connect(application_id, max_connections \\ nil) do
    key = application_id

    if max_connections do
      current = :ets.update_counter(@table, key, {2, 0}, {key, 0})

      if current >= max_connections do
        :limit_reached
      else
        :ets.update_counter(@table, key, {2, 1}, {key, 0})
        :ok
      end
    else
      :ets.update_counter(@table, key, {2, 1}, {key, 0})
      :ok
    end
  end

  @doc """
  Decrements connection count for an application.
  """
  @spec track_disconnect(String.t()) :: :ok
  def track_disconnect(application_id) do
    key = application_id

    case :ets.update_counter(@table, key, {2, -1, 0, 0}, {key, 0}) do
      0 -> :ets.delete_object(@table, {key, 0})
      _ -> :ok
    end

    :ok
  end

  @doc """
  Gets the current connection count for an application.
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
    {:ok, %{table: table}}
  end
end
