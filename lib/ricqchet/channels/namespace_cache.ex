defmodule Ricqchet.Channels.NamespaceCache do
  @moduledoc """
  ETS-based cache for namespace configuration lookups.

  Caches the result of namespace-to-channel matching to avoid repeated
  database queries on the hot path (every event publish). Entries expire
  after a configurable TTL (default 60 seconds).

  The GenServer owns the ETS table; all read/write operations go directly
  to ETS for lock-free concurrency.
  """

  use GenServer

  @table __MODULE__
  @default_ttl_ms 60_000
  @ttl_key :__ttl_ms__

  ## Client API

  @doc """
  Starts the NamespaceCache.

  ## Options

  - `:ttl_ms` - Cache entry time-to-live in milliseconds (default: 60_000)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Looks up a cached namespace for an application + channel combination.

  Returns `{:ok, namespace}` or `{:ok, nil}` on cache hit, `:miss` on cache miss.
  """
  @spec get(String.t(), String.t()) :: {:ok, term()} | :miss
  def get(application_id, channel_name) do
    key = {application_id, channel_name}

    case :ets.lookup(@table, key) do
      [{^key, value, inserted_at}] ->
        if expired?(inserted_at) do
          :ets.delete(@table, key)
          :miss
        else
          {:ok, value}
        end

      [] ->
        :miss
    end
  end

  @doc """
  Stores a namespace (or nil) in the cache for an application + channel combination.
  """
  @spec put(String.t(), String.t(), term()) :: true
  def put(application_id, channel_name, value) do
    key = {application_id, channel_name}
    :ets.insert(@table, {key, value, System.monotonic_time(:millisecond)})
  end

  @doc """
  Invalidates all cache entries for an application.
  """
  @spec invalidate(String.t()) :: :ok
  def invalidate(application_id) do
    match_spec = [
      {{{application_id, :_}, :_, :_}, [], [true]}
    ]

    :ets.select_delete(@table, match_spec)
    :ok
  end

  @doc """
  Clears the entire cache.
  """
  @spec invalidate_all() :: :ok
  def invalidate_all do
    :ets.delete_all_objects(@table)
    :ok
  end

  ## Server Callbacks

  @impl GenServer
  def init(opts) do
    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    table = :ets.new(@table, [:named_table, :public, :set, {:read_concurrency, true}])
    :ets.insert(table, {@ttl_key, ttl_ms, 0})
    {:ok, %{table: table}}
  end

  ## Private

  defp expired?(inserted_at) do
    now = System.monotonic_time(:millisecond)
    ttl_ms = ttl_ms()
    now - inserted_at > ttl_ms
  end

  defp ttl_ms do
    case :ets.lookup(@table, @ttl_key) do
      [{@ttl_key, ttl_ms, _}] -> ttl_ms
      [] -> @default_ttl_ms
    end
  end
end
