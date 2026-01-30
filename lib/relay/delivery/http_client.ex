defmodule Relay.Delivery.HttpClient do
  @moduledoc """
  HTTP client for delivering messages to destination URLs.

  Uses Req with configurable timeouts and telemetry integration.
  """

  alias Relay.Messages.Message

  @receive_timeout 30_000
  @connect_timeout 10_000

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
      connect_timeout: @connect_timeout,
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

    forwarded_headers =
      (message.headers || %{})
      |> Enum.map(fn {key, value} -> {key, value} end)

    base_headers ++ forwarded_headers
  end

  defp method_atom(method) when is_binary(method) do
    method
    |> String.downcase()
    |> String.to_existing_atom()
  end

  defp method_atom(method) when is_atom(method), do: method
end
