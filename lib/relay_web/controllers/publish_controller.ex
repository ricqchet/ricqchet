defmodule RelayWeb.PublishController do
  @moduledoc """
  Controller for publishing messages to the queue.
  """

  use RelayWeb, :controller

  alias Relay.Messages

  action_fallback RelayWeb.FallbackController

  @doc """
  Publishes a message to be delivered to the destination URL.

  The destination URL is captured from the wildcard path parameter.
  Various Relay-* headers control message behavior:

  - `Relay-Delay`: Delay before first attempt (e.g., "30s", "5m", "2h", "1d")
  - `Relay-Dedup-Key`: Deduplication key
  - `Relay-Dedup-TTL`: Dedup window in seconds (default: 300)
  - `Relay-Retries`: Override max retries
  - `Relay-Forward-*`: Headers to forward to destination (prefix stripped)
  """
  def create(conn, %{"destination_url" => destination_parts}) do
    tenant = conn.assigns.current_tenant
    destination_url = build_destination_url(destination_parts)

    attrs =
      %{destination_url: destination_url}
      |> put_payload(conn)
      |> put_content_type(conn)
      |> put_delay(conn)
      |> put_dedup(conn)
      |> put_max_retries(conn)
      |> put_forwarded_headers(conn)

    # Check for existing message with same dedup_key
    case check_dedup(tenant, attrs) do
      {:duplicate, existing_id} ->
        {:error, :duplicate, existing_id}

      :ok ->
        case Messages.create(tenant, attrs) do
          {:ok, message} ->
            conn
            |> put_status(:accepted)
            |> render(:created, message: message)

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp build_destination_url(parts) when is_list(parts) do
    Enum.join(parts, "/")
  end

  defp put_payload(attrs, conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        Map.put(attrs, :payload, body)

      body when is_map(body) ->
        Map.put(attrs, :payload, Jason.encode!(body))

      body ->
        Map.put(attrs, :payload, body)
    end
  end

  defp put_content_type(attrs, conn) do
    case get_req_header(conn, "content-type") do
      [content_type | _] -> Map.put(attrs, :content_type, content_type)
      [] -> attrs
    end
  end

  defp put_delay(attrs, conn) do
    case get_req_header(conn, "relay-delay") do
      [delay | _] -> Map.put(attrs, :delay, parse_delay(delay))
      [] -> attrs
    end
  end

  defp put_dedup(attrs, conn) do
    attrs =
      case get_req_header(conn, "relay-dedup-key") do
        [key | _] -> Map.put(attrs, :dedup_key, key)
        [] -> attrs
      end

    case get_req_header(conn, "relay-dedup-ttl") do
      [ttl | _] -> Map.put(attrs, :dedup_ttl, parse_integer(ttl, 300))
      [] -> attrs
    end
  end

  defp put_max_retries(attrs, conn) do
    case get_req_header(conn, "relay-retries") do
      [retries | _] -> Map.put(attrs, :max_retries, parse_integer(retries, 3))
      [] -> attrs
    end
  end

  defp put_forwarded_headers(attrs, conn) do
    forwarded =
      conn.req_headers
      |> Enum.filter(fn {key, _} -> String.starts_with?(key, "relay-forward-") end)
      |> Enum.map(fn {key, value} ->
        # Strip "relay-forward-" prefix
        header_name = String.replace_prefix(key, "relay-forward-", "")
        {header_name, value}
      end)
      |> Map.new()

    if map_size(forwarded) > 0 do
      Map.put(attrs, :headers, forwarded)
    else
      attrs
    end
  end

  defp check_dedup(tenant, %{dedup_key: dedup_key}) when is_binary(dedup_key) do
    case Messages.get_by_dedup_key(tenant, dedup_key) do
      nil -> :ok
      existing -> {:duplicate, existing.id}
    end
  end

  defp check_dedup(_, _), do: :ok

  # Parse delay string like "30s", "5m", "2h", "1d" to seconds
  defp parse_delay(delay) do
    case Integer.parse(delay) do
      {value, "s"} -> value
      {value, "m"} -> value * 60
      {value, "h"} -> value * 60 * 60
      {value, "d"} -> value * 24 * 60 * 60
      {value, ""} -> value
      _ -> 0
    end
  end

  defp parse_integer(value, default) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end
end
