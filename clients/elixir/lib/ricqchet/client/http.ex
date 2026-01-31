defmodule Ricqchet.Client.HTTP do
  @moduledoc false
  @behaviour Ricqchet.Client.Adapter

  # Internal HTTP client for Ricqchet operations.

  alias Ricqchet.Error

  @impl true
  def publish(config, destination, payload, opts) do
    headers = build_publish_headers(destination, opts)
    body = encode_payload(payload)

    case request(:post, config, "/v1/publish", headers, body) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, %{message_id: body["message_id"]}}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, reason} ->
        {:error, Error.connection_error(reason)}
    end
  end

  @impl true
  def publish_fan_out(config, destinations, payload, opts) do
    fan_out_header = Enum.join(destinations, ", ")
    headers = [{"ricqchet-fan-out", fan_out_header}] ++ build_common_headers(opts)
    body = encode_payload(payload)

    case request(:post, config, "/v1/publish", headers, body) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, %{message_ids: body["message_ids"]}}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, reason} ->
        {:error, Error.connection_error(reason)}
    end
  end

  @impl true
  def get_message(config, message_id) do
    case request(:get, config, "/v1/messages/#{message_id}", [], nil) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, reason} ->
        {:error, Error.connection_error(reason)}
    end
  end

  @impl true
  def cancel_message(config, message_id) do
    case request(:delete, config, "/v1/messages/#{message_id}", [], nil) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 409}} ->
        {:error, :already_dispatched}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, reason} ->
        {:error, Error.connection_error(reason)}
    end
  end

  @impl true
  def get_signing_secret(config) do
    case request(:get, config, "/v1/signing-secret", [], nil) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, Base.decode64!(body["signing_secret"])}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, reason} ->
        {:error, Error.connection_error(reason)}
    end
  end

  # Private helpers

  defp request(method, config, path, headers, body) do
    url = config.base_url <> path

    auth_headers = [
      {"authorization", "Bearer #{config.api_key}"},
      {"content-type", "application/json"},
      {"user-agent", "ricqchet-elixir/0.1.0"}
    ]

    all_headers = auth_headers ++ headers

    opts = [
      method: method,
      url: url,
      headers: all_headers,
      receive_timeout: config.timeout,
      retry: false
    ]

    opts = if body, do: Keyword.put(opts, :body, body), else: opts

    case Req.request(opts) do
      {:ok, response} ->
        {:ok, %{status: response.status, body: response.body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp build_publish_headers(destination, opts) do
    [{"ricqchet-destination", destination}] ++ build_common_headers(opts)
  end

  defp build_common_headers(opts) do
    []
    |> maybe_add_header("ricqchet-delay", opts[:delay])
    |> maybe_add_header("ricqchet-dedup-key", opts[:dedup_key])
    |> maybe_add_header("ricqchet-dedup-ttl", opts[:dedup_ttl])
    |> maybe_add_header("ricqchet-retries", opts[:retries])
    |> maybe_add_header("ricqchet-batch-key", opts[:batch_key])
    |> maybe_add_header("ricqchet-batch-size", opts[:batch_size])
    |> maybe_add_header("ricqchet-batch-timeout", opts[:batch_timeout])
    |> maybe_add_header("content-type", opts[:content_type])
    |> add_forward_headers(opts[:forward_headers])
  end

  defp maybe_add_header(headers, _name, nil), do: headers
  defp maybe_add_header(headers, name, value), do: [{name, to_string(value)} | headers]

  defp add_forward_headers(headers, nil), do: headers

  defp add_forward_headers(headers, forward_headers) when is_map(forward_headers) do
    forwarded =
      Enum.map(forward_headers, fn {key, value} ->
        {"ricqchet-forward-#{key}", value}
      end)

    headers ++ forwarded
  end

  defp encode_payload(payload) when is_binary(payload), do: payload
  defp encode_payload(payload), do: Jason.encode!(payload)
end
