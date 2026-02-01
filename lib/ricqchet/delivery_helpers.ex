defmodule Ricqchet.DeliveryHelpers do
  @moduledoc """
  Shared helper functions for message and batch delivery.

  Contains common logic for retry backoff, error formatting,
  and response body truncation.
  """

  @doc """
  Calculates exponential backoff in seconds for a given attempt number.

  Uses a base of 10 seconds with a multiplier of 3:
  - Attempt 1: 10s
  - Attempt 2: 30s
  - Attempt 3: 90s
  - Attempt 4: 270s
  - etc.

  Capped at 8 hours (28,800 seconds).
  """
  def backoff_seconds(attempt) do
    base = 10
    max_backoff = 8 * 60 * 60

    backoff = trunc(base * :math.pow(3, attempt - 1))
    min(backoff, max_backoff)
  end

  @doc """
  Formats an error into a human-readable string.

  Handles various error formats:
  - Binary strings pass through unchanged
  - `{:http_error, status}` tuples become "HTTP <status>"
  - Maps with `:reason` key extract the reason
  - Other values are inspected
  """
  def format_error(error) when is_binary(error), do: error
  def format_error({:http_error, status}), do: "HTTP #{status}"
  def format_error(%{reason: reason}), do: inspect(reason)
  def format_error(error), do: inspect(error)

  @doc """
  Truncates a response body to a maximum of 10,000 characters.

  Returns nil for nil input. Non-binary values are inspected first.
  """
  def truncate_body(nil), do: nil
  def truncate_body(body) when is_binary(body), do: String.slice(body, 0, 10_000)

  def truncate_body(body) do
    body
    |> inspect()
    |> String.slice(0, 10_000)
  end
end
