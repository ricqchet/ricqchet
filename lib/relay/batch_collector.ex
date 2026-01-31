defmodule Relay.BatchCollector do
  @moduledoc """
  Stateless module for adding messages to batches.

  This module handles the write path for batch collection:
  1. Find or create a collecting batch in the database
  2. Create the message associated with the batch
  3. If batch is ready (size reached), schedule it for immediate dispatch

  The BatchDispatcher polls for ready batches and dispatches them.
  This separation allows horizontal scaling - multiple instances can
  safely add messages to batches using database locks.
  """

  alias Relay.Batches
  alias Relay.Messages
  alias Relay.Repo
  alias Relay.Tenants.Tenant

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
    case Batches.find_or_create_collecting(tenant, destination_url, batch_key, batch_opts) do
      {:ok, batch, _status} ->
        create_and_maybe_dispatch(tenant, batch, message_attrs)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_and_maybe_dispatch(tenant, batch, message_attrs) do
    # Use a transaction to ensure message creation and count increment
    # happen atomically - prevents race condition where message exists
    # but count was never incremented
    Repo.transaction(fn ->
      case Messages.create_for_batch(tenant, batch, message_attrs) do
        {:ok, message} ->
          handle_message_count_increment(batch)
          message

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp handle_message_count_increment(batch) do
    case Batches.increment_message_count(batch) do
      {:ok, updated_batch, :ready} ->
        Batches.schedule_for_immediate_dispatch(updated_batch)

      {:ok, _updated_batch, :collecting} ->
        :ok

      {:error, reason} ->
        # Log the error but don't fail the message creation
        # The batch will eventually be dispatched by timeout
        require Logger
        Logger.warning("Failed to increment batch count: #{inspect(reason)}")
    end
  end
end
