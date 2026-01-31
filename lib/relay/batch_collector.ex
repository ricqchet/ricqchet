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
    case Messages.create_for_batch(tenant, batch, message_attrs) do
      {:ok, message} ->
        {:ok, updated_batch, status} = Batches.increment_message_count(batch)

        if status == :ready do
          Batches.schedule_for_immediate_dispatch(updated_batch)
        end

        {:ok, message}

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
