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

  alias Ricqchet.Channels
  alias Ricqchet.Delivery.HttpClient
  alias Ricqchet.FlowControl
  alias Ricqchet.Messages

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id}}) do
    case Messages.get_for_delivery(message_id) do
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

    try do
      result = HttpClient.deliver(message)
      handle_result(message, result)
      :ok
    after
      # Always release flow control slot, regardless of success/failure
      FlowControl.release_slot(message)
    end
  end

  defp handle_result(message, {:ok, %{status: status} = response}) when status in 200..299 do
    Logger.info("Message #{message.id} delivered successfully (status: #{status})")

    Messages.mark_delivered(message, response)
    maybe_broadcast_to_channel(message)
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

  defp maybe_broadcast_to_channel(message) do
    case get_channel_header(message.headers) do
      nil ->
        :ok

      channel_name ->
        broadcast_to_channel(message, channel_name)
    end
  end

  defp broadcast_to_channel(message, channel_name) do
    data = %{
      message_id: message.id,
      destination_url: message.destination_url,
      payload: message.payload
    }

    Channels.publish_event(
      message.application_id,
      channel_name,
      "relay:message",
      data,
      tenant_id: message.tenant_id
    )

    :ok
  rescue
    error ->
      Logger.warning("Failed to broadcast message to channel",
        message_id: message.id,
        channel: channel_name,
        reason: inspect(error)
      )

      :ok
  end

  defp get_channel_header(nil), do: nil

  defp get_channel_header(headers) when is_map(headers) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == "ricqchet-channel", do: value
    end)
  end
end
