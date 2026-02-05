defmodule Ricqchet.FlowControl.SettingsCache do
  @moduledoc """
  ETS cache for destination flow control settings.

  Caches flow control settings to avoid database queries on the hot path
  (message dispatch). Settings are cached with a TTL and invalidated when
  destination settings change.

  ## Cache Structure

  Key: destination_id (binary UUID)
  Value: {parallelism, rate_limit, cached_at}
  """

  use GenServer

  @table_name :flow_control_settings_cache
  @ttl_key :__ttl__
  @default_ttl_ms 60_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets cached settings for a destination.

  Returns `{:ok, {parallelism, rate_limit}}` if cached and not expired,
  `:miss` otherwise.
  """
  def get(destination_id) do
    case :ets.lookup(@table_name, destination_id) do
      [{^destination_id, parallelism, rate_limit, cached_at}] ->
        if expired?(cached_at) do
          # Clean up expired entry to prevent memory accumulation
          :ets.delete(@table_name, destination_id)
          :miss
        else
          {:ok, {parallelism, rate_limit}}
        end

      [] ->
        :miss
    end
  end

  @doc """
  Stores settings in the cache.
  """
  def put(destination_id, parallelism, rate_limit) do
    cached_at = System.monotonic_time(:millisecond)
    :ets.insert(@table_name, {destination_id, parallelism, rate_limit, cached_at})
    :ok
  end

  @doc """
  Invalidates cache for a specific destination.
  """
  def invalidate(destination_id) do
    :ets.delete(@table_name, destination_id)
    :ok
  end

  @doc """
  Invalidates all cached settings.
  """
  def invalidate_all do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  # Server Callbacks

  @impl GenServer
  def init(opts) do
    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    # Store TTL in ETS to avoid GenServer calls on the hot path
    :ets.insert(@table_name, {@ttl_key, ttl_ms})
    {:ok, %{ttl_ms: ttl_ms}}
  end

  # Private

  defp expired?(cached_at) do
    ttl_ms = get_ttl()
    now = System.monotonic_time(:millisecond)
    now - cached_at > ttl_ms
  end

  defp get_ttl do
    case :ets.lookup(@table_name, @ttl_key) do
      [{@ttl_key, ttl_ms}] -> ttl_ms
      [] -> @default_ttl_ms
    end
  end
end
