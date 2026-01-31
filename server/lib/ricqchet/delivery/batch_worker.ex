defmodule Ricqchet.Delivery.BatchWorker do
  @moduledoc """
  Oban worker for delivering batches of messages.

  Collects all message payloads for a batch, combines them into a JSON array,
  and delivers to the destination URL.
  """

  use Oban.Worker,
    queue: :delivery,
    max_attempts: 1

  require Logger

  alias Ricqchet.Batches
  alias Ricqchet.Delivery.HttpClient

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"batch_id" => batch_id}}) do
    batch = Batches.get_for_delivery!(batch_id)
    payloads = Batches.get_batch_payloads(batch)

    Logger.info(
      "Delivering batch #{batch_id} with #{length(payloads)} messages to #{batch.destination_url} " <>
        "(attempt #{batch.attempts + 1})"
    )

    # Combine payloads into JSON array
    combined_payload = Jason.encode!(payloads)

    result = HttpClient.deliver_batch(batch, combined_payload)
    handle_result(batch, result)

    :ok
  end

  defp handle_result(batch, {:ok, %{status: status} = response}) when status in 200..299 do
    Logger.info("Batch #{batch.id} delivered successfully (status: #{status})")

    Batches.mark_delivered(batch, response)
  end

  defp handle_result(batch, {:ok, response}) do
    Logger.warning(
      "Batch #{batch.id} delivery failed with status #{response.status} " <>
        "(attempt #{batch.attempts + 1}/#{batch.max_retries})"
    )

    Batches.mark_failed(batch, {:http_error, response.status}, %{
      status: response.status,
      body: response.body
    })
  end

  defp handle_result(batch, {:error, %{reason: reason}}) do
    Logger.warning(
      "Batch #{batch.id} delivery failed: #{inspect(reason)} " <>
        "(attempt #{batch.attempts + 1}/#{batch.max_retries})"
    )

    Batches.mark_failed(batch, reason, nil)
  end

  defp handle_result(batch, {:error, reason}) do
    Logger.warning(
      "Batch #{batch.id} delivery failed: #{inspect(reason)} " <>
        "(attempt #{batch.attempts + 1}/#{batch.max_retries})"
    )

    Batches.mark_failed(batch, reason, nil)
  end
end
