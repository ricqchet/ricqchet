defmodule Relay.BatchCollector do
  @moduledoc """
  GenServer that manages batch collection and triggers dispatch.

  When a message is added to a batch:
  1. Find or create a collecting batch in the database
  2. Create the message associated with the batch
  3. If this is a new batch, schedule a timeout timer
  4. If batch is ready (size reached), dispatch immediately

  When a timeout fires:
  1. Check if batch is still collecting
  2. If yes, dispatch it
  """

  use GenServer

  require Logger

  alias Relay.Batches
  alias Relay.Delivery.BatchWorker
  alias Relay.Messages
  alias Relay.Tenants.Tenant

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Adds a message to a batch.

  Returns `{:ok, message}` on success.
  """
  def add_message(
        %Tenant{} = tenant,
        batch_key,
        destination_url,
        message_attrs,
        batch_opts \\ %{}
      ) do
    GenServer.call(
      __MODULE__,
      {:add_message, tenant, batch_key, destination_url, message_attrs, batch_opts}
    )
  end

  # Server callbacks

  @impl GenServer
  def init(_opts) do
    # State: map of batch_id => timer_ref
    {:ok, %{timers: %{}}}
  end

  @impl GenServer
  def handle_call(
        {:add_message, tenant, batch_key, destination_url, message_attrs, batch_opts},
        _from,
        state
      ) do
    case do_add_message(tenant, batch_key, destination_url, message_attrs, batch_opts, state) do
      {:ok, message, new_state} ->
        {:reply, {:ok, message}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:batch_timeout, batch_id}, state) do
    Logger.debug("Batch timeout triggered for batch #{batch_id}")

    # Remove timer from state
    new_state = %{state | timers: Map.delete(state.timers, batch_id)}

    # Try to dispatch the batch
    dispatch_batch(batch_id)

    {:noreply, new_state}
  end

  # Private functions

  defp do_add_message(tenant, batch_key, destination_url, message_attrs, batch_opts, state) do
    case Batches.find_or_create_collecting(tenant, destination_url, batch_key, batch_opts) do
      {:ok, batch, :new} ->
        handle_new_batch(tenant, batch, message_attrs, state)

      {:ok, batch, :existing} ->
        handle_existing_batch(tenant, batch, message_attrs, state)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_new_batch(tenant, batch, message_attrs, state) do
    case Messages.create_for_batch(tenant, batch, message_attrs) do
      {:ok, message} ->
        # Increment count
        {:ok, _updated_batch, status} = Batches.increment_message_count(batch)

        # Schedule timeout timer
        timer_ref = schedule_timeout(batch.id, batch.timeout_seconds)
        new_state = %{state | timers: Map.put(state.timers, batch.id, timer_ref)}

        # Check if ready to dispatch immediately
        if status == :ready do
          final_state = cancel_and_dispatch(batch.id, new_state)
          {:ok, message, final_state}
        else
          {:ok, message, new_state}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp handle_existing_batch(tenant, batch, message_attrs, state) do
    case Messages.create_for_batch(tenant, batch, message_attrs) do
      {:ok, message} ->
        # Increment count
        {:ok, _updated_batch, status} = Batches.increment_message_count(batch)

        # Check if ready to dispatch
        if status == :ready do
          new_state = cancel_and_dispatch(batch.id, state)
          {:ok, message, new_state}
        else
          {:ok, message, state}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp schedule_timeout(batch_id, timeout_seconds) do
    timeout_ms = timeout_seconds * 1000
    Process.send_after(self(), {:batch_timeout, batch_id}, timeout_ms)
  end

  defp cancel_and_dispatch(batch_id, state) do
    # Cancel any existing timer
    case Map.get(state.timers, batch_id) do
      nil -> :ok
      timer_ref -> Process.cancel_timer(timer_ref)
    end

    # Dispatch the batch
    dispatch_batch(batch_id)

    # Return updated state with timer removed
    %{state | timers: Map.delete(state.timers, batch_id)}
  end

  defp dispatch_batch(batch_id) do
    case Batches.get(batch_id) do
      nil ->
        Logger.warning("Batch #{batch_id} not found for dispatch")

      batch ->
        dispatch_if_collecting(batch)
    end
  end

  defp dispatch_if_collecting(%{status: "collecting"} = batch) do
    case Batches.mark_dispatched(batch) do
      {:ok, updated_batch} ->
        enqueue_batch_delivery(updated_batch)

      {:error, reason} ->
        Logger.error("Failed to mark batch #{batch.id} as dispatched: #{inspect(reason)}")
    end
  end

  defp dispatch_if_collecting(batch) do
    Logger.debug("Batch #{batch.id} already dispatched (status: #{batch.status})")
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
