defmodule Relay.Dispatcher do
  @moduledoc """
  GenServer that polls for pending messages and dispatches them for delivery.

  Runs on a configurable interval (default 100ms) and claims pending messages
  that are ready for delivery (scheduled_at <= now). For each claimed message,
  it inserts an Oban job for the delivery worker.
  """

  use GenServer

  require Logger

  alias Relay.Delivery.Worker
  alias Relay.Messages

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
    dispatch_pending()
    schedule_poll()
    {:noreply, state}
  end

  # Private functions

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  defp dispatch_pending do
    case Messages.claim_next_pending() do
      {:ok, message} ->
        enqueue_delivery(message)
        # Try to dispatch more messages
        dispatch_pending()

      {:error, :none_available} ->
        :ok
    end
  end

  defp enqueue_delivery(message) do
    job = Worker.new(%{message_id: message.id})

    case Oban.insert(job) do
      {:ok, _job} ->
        Logger.debug("Enqueued delivery for message #{message.id}")

      {:error, reason} ->
        Logger.error("Failed to enqueue delivery for message #{message.id}: #{inspect(reason)}")
    end
  end
end
