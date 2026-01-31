defmodule Ricqchet.Dispatcher do
  @moduledoc """
  GenServer that polls for pending messages and dispatches them for delivery.

  Runs on a configurable interval (default 100ms) and claims pending messages
  that are ready for delivery (scheduled_at <= now). For each claimed message,
  it inserts an Oban job for the delivery worker.

  ## Configuration

  Configure in your application config:

      config :ricqchet, Ricqchet.Dispatcher,
        poll_interval_ms: 100,
        max_messages_per_cycle: 100
  """

  use GenServer

  require Logger

  alias Ricqchet.Delivery.Worker
  alias Ricqchet.Messages

  @default_poll_interval_ms 100
  @default_max_messages_per_cycle 100

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
    dispatch_pending(max_messages_per_cycle())
    schedule_poll()
    {:noreply, state}
  end

  # Private functions

  defp schedule_poll do
    Process.send_after(self(), :poll, poll_interval_ms())
  end

  defp dispatch_pending(0), do: :ok

  defp dispatch_pending(remaining) do
    case Messages.claim_next_pending() do
      {:ok, message} ->
        enqueue_delivery(message)
        dispatch_pending(remaining - 1)

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
        # Revert status to prevent message from being stuck in "dispatched" forever
        Messages.revert_to_pending(message)
    end
  end

  defp poll_interval_ms do
    config = Application.get_env(:ricqchet, __MODULE__, [])
    Keyword.get(config, :poll_interval_ms, @default_poll_interval_ms)
  end

  defp max_messages_per_cycle do
    config = Application.get_env(:ricqchet, __MODULE__, [])
    Keyword.get(config, :max_messages_per_cycle, @default_max_messages_per_cycle)
  end
end
