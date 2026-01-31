defmodule Ricqchet.Dlq.NotificationWorker do
  @moduledoc """
  Oban worker for sending DLQ webhook notifications.

  When a message or batch permanently fails delivery, this worker sends
  a notification to the application's configured DLQ destination URL.

  The webhook payload includes details about the failed entity and the
  associated application and tenant for context.
  """

  use Oban.Worker,
    queue: :dlq_notifications,
    max_attempts: 3

  require Logger

  alias Ricqchet.Batches
  alias Ricqchet.Messages
  alias Ricqchet.Repo
  alias Ricqchet.UrlValidator

  @receive_timeout 30_000
  @connect_timeout 10_000

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"type" => "message", "entity_id" => id, "destination_url" => url}
      }) do
    with {:ok, message} <- get_message(id),
         message <- Repo.preload(message, application: :tenant),
         :ok <- UrlValidator.validate_url(url) do
      send_notification(url, build_message_payload(message))
    end
  end

  def perform(%Oban.Job{args: %{"type" => "batch", "entity_id" => id, "destination_url" => url}}) do
    with {:ok, batch} <- get_batch(id),
         batch <- Repo.preload(batch, application: :tenant),
         :ok <- UrlValidator.validate_url(url) do
      send_notification(url, build_batch_payload(batch))
    end
  end

  defp get_message(id) do
    case Messages.get(id) do
      nil -> {:error, :not_found}
      message -> {:ok, message}
    end
  end

  defp get_batch(id) do
    case Batches.get(id) do
      nil -> {:error, :not_found}
      batch -> {:ok, batch}
    end
  end

  defp build_message_payload(message) do
    %{
      event: "message.failed",
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      message: %{
        id: message.id,
        destination_url: message.destination_url,
        method: message.method,
        status: message.status,
        attempts: message.attempts,
        max_retries: message.max_retries,
        last_error: message.last_error,
        last_response_status: message.last_response_status,
        created_at: format_datetime(message.inserted_at),
        failed_at: format_datetime(message.completed_at)
      },
      application: build_application_info(message.application),
      tenant: build_tenant_info(message.application)
    }
  end

  defp build_batch_payload(batch) do
    %{
      event: "batch.failed",
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      batch: %{
        id: batch.id,
        destination_url: batch.destination_url,
        batch_key: batch.batch_key,
        message_count: batch.message_count,
        status: batch.status,
        attempts: batch.attempts,
        max_retries: batch.max_retries,
        last_error: batch.last_error,
        last_response_status: batch.last_response_status,
        created_at: format_datetime(batch.inserted_at),
        failed_at: format_datetime(batch.completed_at)
      },
      application: build_application_info(batch.application),
      tenant: build_tenant_info(batch.application)
    }
  end

  defp build_application_info(nil), do: nil

  defp build_application_info(app) do
    %{id: app.id, name: app.name}
  end

  defp build_tenant_info(nil), do: nil
  defp build_tenant_info(%{tenant: nil}), do: nil

  defp build_tenant_info(%{tenant: tenant}) do
    %{id: tenant.id, name: tenant.name}
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(datetime), do: DateTime.to_iso8601(datetime)

  defp send_notification(url, payload) do
    case Req.post(url,
           json: payload,
           headers: [
             {"user-agent", "Ricqchet-DLQ/1.0"},
             {"content-type", "application/json"}
           ],
           receive_timeout: @receive_timeout,
           connect_options: [timeout: @connect_timeout],
           retry: false
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.info("DLQ notification sent successfully to #{url}")
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning("DLQ notification failed with status #{status}: #{inspect(body)}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.warning("DLQ notification failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
