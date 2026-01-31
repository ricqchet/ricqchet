defmodule Ricqchet.Delivery.HttpClient do
  @moduledoc """
  HTTP client for delivering messages to destination URLs.

  Uses Req with configurable timeouts and telemetry integration.
  Validates URLs at delivery time to prevent SSRF attacks.
  """

  alias Ricqchet.Batches.Batch
  alias Ricqchet.Messages.Message
  alias Ricqchet.UrlValidator

  @receive_timeout 30_000
  @connect_timeout 10_000

  @connect_options [timeout: @connect_timeout]

  # Explicit mapping of HTTP methods to atoms (avoids String.to_existing_atom crash)
  @method_map %{
    "get" => :get,
    "post" => :post,
    "put" => :put,
    "patch" => :patch,
    "delete" => :delete,
    "head" => :head,
    "options" => :options
  }

  @doc """
  Delivers a message to its destination URL.

  Returns `{:ok, response}` on success or `{:error, reason}` on failure.
  Validates the URL at delivery time as defense-in-depth against DNS rebinding.
  """
  def deliver(%Message{} = message) do
    with :ok <- UrlValidator.validate_url(message.destination_url) do
      headers = build_headers(message)

      Req.request(
        method: method_atom(message.method),
        url: message.destination_url,
        headers: headers,
        body: message.payload,
        receive_timeout: @receive_timeout,
        connect_options: @connect_options,
        retry: false
      )
    end
  end

  @doc """
  Delivers a batch of messages as a JSON array.

  Returns `{:ok, response}` on success or `{:error, reason}` on failure.
  Validates the URL at delivery time as defense-in-depth against DNS rebinding.
  """
  def deliver_batch(%Batch{} = batch, combined_payload) do
    with :ok <- UrlValidator.validate_url(batch.destination_url) do
      headers = build_batch_headers(batch)

      Req.request(
        method: method_atom(batch.method),
        url: batch.destination_url,
        headers: headers,
        body: combined_payload,
        receive_timeout: @receive_timeout,
        connect_options: @connect_options,
        retry: false
      )
    end
  end

  defp build_headers(message) do
    base_headers = [
      {"content-type", message.content_type || "application/json"},
      {"user-agent", "Ricqchet/1.0"},
      {"x-ricqchet-message-id", message.id},
      {"x-ricqchet-attempt", to_string(message.attempts + 1)}
    ]

    forwarded_headers = Map.to_list(message.headers || %{})

    base_headers ++ forwarded_headers
  end

  defp build_batch_headers(batch) do
    base_headers = [
      {"content-type", "application/json"},
      {"user-agent", "Ricqchet/1.0"},
      {"x-ricqchet-batch-id", batch.id},
      {"x-ricqchet-batch-size", to_string(batch.message_count)},
      {"x-ricqchet-attempt", to_string(batch.attempts + 1)}
    ]

    forwarded_headers = Map.to_list(batch.headers || %{})

    base_headers ++ forwarded_headers
  end

  defp method_atom(method) when is_binary(method) do
    Map.fetch!(@method_map, String.downcase(method))
  end

  defp method_atom(method) when is_atom(method), do: method
end
