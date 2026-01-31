defmodule Ricqchet.Delivery.Worker do
  @moduledoc """
  Oban worker for delivering messages to their destination URLs.

  Handles successful delivery, failures, and retry scheduling with
  exponential backoff.
  """

  use Oban.Worker,
    queue: :delivery,
    max_attempts: 1

  require Logger

  alias Ricqchet.Delivery.HttpClient
  alias Ricqchet.Messages

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id}}) do
    case Messages.get(message_id) do
      nil ->
        # Message was deleted between enqueue and delivery
        Logger.info("Message #{message_id} not found, likely deleted")
        :ok

      message ->
        deliver_message(message)
    end
  end

  defp deliver_message(message) do
    Logger.info(
      "Delivering message #{message.id} to #{message.destination_url} (attempt #{message.attempts + 1})"
    )

    result = HttpClient.deliver(message)
    handle_result(message, result)

    :ok
  end

  defp handle_result(message, {:ok, %{status: status} = response}) when status in 200..299 do
    Logger.info("Message #{message.id} delivered successfully (status: #{status})")

    Messages.mark_delivered(message, response)
  end

  defp handle_result(message, {:ok, response}) do
    Logger.warning(
      "Message #{message.id} delivery failed with status #{response.status} " <>
        "(attempt #{message.attempts + 1}/#{message.max_retries})"
    )

    Messages.mark_failed(message, {:http_error, response.status}, %{
      status: response.status,
      body: response.body
    })
  end

  defp handle_result(message, {:error, %{reason: reason}}) do
    Logger.warning(
      "Message #{message.id} delivery failed: #{inspect(reason)} " <>
        "(attempt #{message.attempts + 1}/#{message.max_retries})"
    )

    Messages.mark_failed(message, reason, nil)
  end

  defp handle_result(message, {:error, reason}) do
    Logger.warning(
      "Message #{message.id} delivery failed: #{inspect(reason)} " <>
        "(attempt #{message.attempts + 1}/#{message.max_retries})"
    )

    Messages.mark_failed(message, reason, nil)
  end
end
