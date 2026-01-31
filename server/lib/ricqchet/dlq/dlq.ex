defmodule Ricqchet.Dlq do
  @moduledoc """
  Context module for Dead Letter Queue (DLQ) operations.

  Handles notifications when messages or batches permanently fail delivery.
  When a message or batch exhausts its retry attempts, this module checks
  if the associated application has a DLQ destination configured and
  enqueues a notification to be sent to that URL.
  """

  alias Ricqchet.Applications
  alias Ricqchet.Dlq.NotificationWorker
  alias Ricqchet.Repo

  @doc """
  Enqueues a DLQ notification if the entity has an associated application
  with a DLQ destination configured.

  For messages without an application_id, this is a no-op.
  For applications without a dlq_destination_url, this is a no-op.

  Returns `:ok` in all cases to avoid blocking the caller.
  """
  def maybe_notify_failure(%Ricqchet.Messages.Message{application_id: nil}), do: :ok

  def maybe_notify_failure(%Ricqchet.Messages.Message{} = message) do
    message = Repo.preload(message, :application)

    case Applications.get_dlq_destination(message.application) do
      nil -> :ok
      "" -> :ok
      url -> enqueue_notification(:message, message.id, url)
    end
  end

  def maybe_notify_failure(%Ricqchet.Batches.Batch{application_id: nil}), do: :ok

  def maybe_notify_failure(%Ricqchet.Batches.Batch{} = batch) do
    batch = Repo.preload(batch, :application)

    case Applications.get_dlq_destination(batch.application) do
      nil -> :ok
      "" -> :ok
      url -> enqueue_notification(:batch, batch.id, url)
    end
  end

  defp enqueue_notification(type, entity_id, destination_url) do
    %{
      type: to_string(type),
      entity_id: entity_id,
      destination_url: destination_url
    }
    |> NotificationWorker.new()
    |> Oban.insert()

    :ok
  end
end
