defmodule Relay.Delivery.HttpClient do
  @moduledoc """
  HTTP client for delivering messages to destination URLs.

  Uses Req with configurable timeouts and telemetry integration.
  """

  alias Relay.Batches.Batch
  alias Relay.Messages.Message

  @receive_timeout 30_000
  @connect_timeout 10_000

  @connect_options [timeout: @connect_timeout]

  @doc """
  Delivers a message to its destination URL.

  Returns `{:ok, response}` on success or `{:error, reason}` on failure.
  """
  def deliver(%Message{} = message) do
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

  @doc """
  Delivers a batch of messages as a JSON array.

  Returns `{:ok, response}` on success or `{:error, reason}` on failure.
  """
  def deliver_batch(%Batch{} = batch, combined_payload) do
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

  defp build_headers(message) do
    base_headers = [
      {"content-type", message.content_type || "application/json"},
      {"user-agent", "Relay/1.0"},
      {"x-relay-message-id", message.id},
      {"x-relay-attempt", to_string(message.attempts + 1)}
    ]

    forwarded_headers = Map.to_list(message.headers || %{})

    base_headers ++ forwarded_headers
  end

  defp build_batch_headers(batch) do
    base_headers = [
      {"content-type", "application/json"},
      {"user-agent", "Relay/1.0"},
      {"x-relay-batch-id", batch.id},
      {"x-relay-batch-size", to_string(batch.message_count)},
      {"x-relay-attempt", to_string(batch.attempts + 1)}
    ]

    forwarded_headers = Map.to_list(batch.headers || %{})

    base_headers ++ forwarded_headers
  end

  defp method_atom(method) when is_binary(method) do
    method
    |> String.downcase()
    |> String.to_existing_atom()
  end

  defp method_atom(method) when is_atom(method), do: method
end
