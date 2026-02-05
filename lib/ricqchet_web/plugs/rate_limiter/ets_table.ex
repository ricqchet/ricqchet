defmodule RicqchetWeb.Plugs.RateLimiter.ETSTable do
  @moduledoc """
  Manages the ETS table for the rate limiter.

  This module is started as part of the application supervision tree to ensure
  the ETS table exists before any requests are processed, avoiding race conditions
  when multiple concurrent requests try to create the table.
  """

  use GenServer

  @table_name :ricqchet_rate_limiter

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Returns the ETS table name used by the rate limiter.
  """
  def table_name, do: @table_name

  @impl GenServer
  def init(_opts) do
    :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      {:write_concurrency, true},
      {:read_concurrency, true}
    ])

    {:ok, %{}}
  end
end
