defmodule Ricqchet.Channels.SubscriberTracker do
  @moduledoc """
  ETS-based subscriber counter for active channels.

  Tracks the number of WebSocket subscribers per channel per application
  using atomic ETS counter operations. This is used to power the
  `GET /v1/channels` and `GET /v1/channels/:channel_name` endpoints.

  The GenServer owns the ETS table; all read/write operations go directly
  to ETS for lock-free concurrency.
  """

  use GenServer

  @table __MODULE__

  ## Client API

  @doc """
  Starts the SubscriberTracker.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Increments the subscriber count for a channel.

  Returns `:first_subscriber` if the count went from 0 to 1,
  otherwise `:ok`.
  """
  @spec track_join(String.t(), String.t()) :: :first_subscriber | :ok
  def track_join(application_id, channel_name) do
    key = {application_id, channel_name}
    count = :ets.update_counter(@table, key, {2, 1}, {key, 0})

    if count == 1, do: :first_subscriber, else: :ok
  end

  @doc """
  Decrements the subscriber count for a channel.

  Returns `:last_subscriber` if the count went from 1 to 0,
  otherwise `:ok`. Cleans up the ETS entry when count reaches 0.
  """
  @spec track_leave(String.t(), String.t()) :: :last_subscriber | :ok
  def track_leave(application_id, channel_name) do
    key = {application_id, channel_name}

    case :ets.update_counter(@table, key, {2, -1, 0, 0}, {key, 0}) do
      0 ->
        # Use delete_object to avoid racing with a concurrent track_join
        # that may have already incremented the counter above 0.
        :ets.delete_object(@table, {key, 0})
        :last_subscriber

      _ ->
        :ok
    end
  end

  @doc """
  Gets the current subscriber count for a channel.
  """
  @spec get_count(String.t(), String.t()) :: non_neg_integer()
  def get_count(application_id, channel_name) do
    key = {application_id, channel_name}

    case :ets.lookup(@table, key) do
      [{^key, count}] -> count
      [] -> 0
    end
  end

  @doc """
  Lists all active channels for an application with their subscriber counts.

  Returns a list of `{channel_name, subscriber_count}` tuples.
  """
  @spec list_active(String.t()) :: [{String.t(), non_neg_integer()}]
  def list_active(application_id) do
    match_spec = [
      {{{application_id, :"$1"}, :"$2"}, [{:>, :"$2", 0}], [{{:"$1", :"$2"}}]}
    ]

    :ets.select(@table, match_spec)
  end

  ## Server Callbacks

  @impl GenServer
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set, {:write_concurrency, true}])
    {:ok, %{table: table}}
  end
end
