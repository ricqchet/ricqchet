defmodule Relay.BatchDispatcher do
  @moduledoc """
  GenServer that polls for ready batches and dispatches them for delivery.

  Runs on a configurable interval (default 100ms) and claims batches that
  are ready for dispatch. A batch is ready when:
  - status is "collecting" AND
  - (message_count >= max_size OR scheduled_at <= now)

  For each claimed batch, it inserts an Oban job for the BatchWorker.

  This design allows horizontal scaling - multiple instances can safely
  poll for batches using PostgreSQL's `FOR UPDATE SKIP LOCKED`.

  ## Configuration

  Configure in your application config:

      config :relay, Relay.BatchDispatcher,
        poll_interval_ms: 100,
        max_batches_per_cycle: 50
  """

  use GenServer

  require Logger

  alias Relay.Batches
  alias Relay.Delivery.BatchWorker

  @default_poll_interval_ms 100
  @default_max_batches_per_cycle 50

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server callbacks

  @impl GenServer
  def init(_opts) do
    schedule_poll()
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    dispatch_ready_batches(max_batches_per_cycle())
    schedule_poll()
    {:noreply, state}
  end

  # Private functions

  defp schedule_poll do
    Process.send_after(self(), :poll, poll_interval_ms())
  end

  defp dispatch_ready_batches(0), do: :ok

  defp dispatch_ready_batches(remaining) do
    case Batches.claim_next_ready() do
      {:ok, batch} ->
        enqueue_batch_delivery(batch)
        dispatch_ready_batches(remaining - 1)

      {:error, :none_available} ->
        :ok
    end
  end

  defp enqueue_batch_delivery(batch) do
    job = BatchWorker.new(%{batch_id: batch.id})

    case Oban.insert(job) do
      {:ok, _job} ->
        Logger.debug("Enqueued batch delivery for batch #{batch.id}")

      {:error, reason} ->
        Logger.error("Failed to enqueue batch delivery for batch #{batch.id}: #{inspect(reason)}")
    end
  end

  defp poll_interval_ms do
    config = Application.get_env(:relay, __MODULE__, [])
    Keyword.get(config, :poll_interval_ms, @default_poll_interval_ms)
  end

  defp max_batches_per_cycle do
    config = Application.get_env(:relay, __MODULE__, [])
    Keyword.get(config, :max_batches_per_cycle, @default_max_batches_per_cycle)
  end
end
