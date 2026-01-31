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
  """

  use GenServer

  require Logger

  alias Relay.Batches
  alias Relay.Delivery.BatchWorker

  @poll_interval_ms 100

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
    dispatch_ready_batches()
    schedule_poll()
    {:noreply, state}
  end

  # Private functions

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  defp dispatch_ready_batches do
    case Batches.claim_next_ready() do
      {:ok, batch} ->
        enqueue_batch_delivery(batch)
        # Try to dispatch more batches
        dispatch_ready_batches()

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
end
