defmodule Ricqchet.Channels.WebhookNotifier do
  @moduledoc """
  Oban worker for sending channel lifecycle and presence webhooks.

  Delivers webhook notifications for channel events:
  - `channel:occupied` — first subscriber joins a channel
  - `channel:vacated` — last subscriber leaves a channel
  - `member:added` — a user joins a presence channel
  - `member:removed` — a user leaves a presence channel

  Webhook URLs are resolved from namespace configuration first, falling
  back to the application-level `channels_webhook_url`. Payloads are
  signed with the tenant's signing secret using HMAC-SHA256.
  """

  use Oban.Worker,
    queue: :channel_webhooks,
    max_attempts: 3

  require Logger

  alias Ricqchet.Applications
  alias Ricqchet.Channels.NamespaceConfig
  alias Ricqchet.Delivery.Signer
  alias Ricqchet.Repo
  alias Ricqchet.UrlValidator

  @receive_timeout 15_000
  @connect_timeout 5_000

  @doc """
  Enqueues a webhook notification job.

  ## Parameters

  - `event` — one of `"channel:occupied"`, `"channel:vacated"`,
    `"member:added"`, `"member:removed"`
  - `attrs` — map with `:application_id`, `:channel_name`, and
    optionally `:user_id` and `:user_info`
  """
  def enqueue(event, attrs) do
    %{
      event: event,
      application_id: attrs.application_id,
      channel_name: attrs.channel_name,
      user_id: Map.get(attrs, :user_id),
      user_info: Map.get(attrs, :user_info),
      timestamp: DateTime.to_iso8601(DateTime.utc_now())
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "event" => event,
            "application_id" => application_id,
            "channel_name" => channel_name
          } = args
      }) do
    with {:ok, url} <- resolve_webhook_url(application_id, channel_name),
         :ok <- validate_url(url),
         {:ok, application} <- get_application(application_id) do
      payload = build_payload(event, channel_name, args)
      send_webhook(url, payload, application)
    else
      {:error, :no_webhook_url} ->
        :ok

      {:error, :not_found} ->
        Logger.warning("Webhook application not found",
          application_id: application_id,
          event: event
        )

        :ok

      {:error, :invalid_url} ->
        Logger.warning("Webhook URL validation failed",
          application_id: application_id,
          event: event
        )

        :ok
    end
  end

  defp resolve_webhook_url(application_id, channel_name) do
    namespace_url =
      case NamespaceConfig.get_namespace_for_channel(application_id, channel_name) do
        {:ok, %{webhook_url: url}} when is_binary(url) and url != "" -> url
        _ -> nil
      end

    if namespace_url do
      {:ok, namespace_url}
    else
      case get_application(application_id) do
        {:ok, app} when is_binary(app.channels_webhook_url) and app.channels_webhook_url != "" ->
          {:ok, app.channels_webhook_url}

        _ ->
          {:error, :no_webhook_url}
      end
    end
  end

  defp validate_url(url) do
    case UrlValidator.validate_url(url) do
      :ok -> :ok
      {:error, _} -> {:error, :invalid_url}
    end
  end

  defp get_application(application_id) do
    case Applications.get_application(application_id) do
      nil -> {:error, :not_found}
      app -> {:ok, Repo.preload(app, :tenant)}
    end
  end

  defp build_payload(event, channel_name, args) do
    %{event: event, channel: channel_name, timestamp: args["timestamp"]}
    |> maybe_put(:user_id, args["user_id"])
    |> maybe_put(:user_info, args["user_info"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp send_webhook(url, payload, application) do
    json_payload = Jason.encode!(payload)

    base_headers = [
      {"content-type", "application/json"},
      {"user-agent", "Ricqchet-Channels/1.0"}
    ]

    headers = maybe_add_signature(base_headers, json_payload, application)

    case Req.post(url,
           body: json_payload,
           headers: headers,
           receive_timeout: @receive_timeout,
           connect_options: [timeout: @connect_timeout],
           retry: false
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status}} ->
        Logger.warning("Channel webhook failed",
          url: url,
          status: status,
          event: payload.event
        )

        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.warning("Channel webhook request failed",
          url: url,
          reason: inspect(reason),
          event: payload.event
        )

        {:error, reason}
    end
  end

  defp maybe_add_signature(headers, payload, %{tenant: %{signing_secret: secret}})
       when is_binary(secret) do
    signature = Signer.sign(payload, secret)
    [{"x-ricqchet-signature", signature} | headers]
  end

  defp maybe_add_signature(headers, _payload, _application), do: headers
end
