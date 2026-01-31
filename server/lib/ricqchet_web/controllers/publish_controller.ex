defmodule RicqchetWeb.PublishController do
  @moduledoc """
  Controller for publishing messages to the queue.
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ricqchet.BatchCollector
  alias Ricqchet.Messages
  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  # Maximum number of destinations for fan-out
  @max_fan_out_destinations 100

  tags(["messages"])

  operation(:create,
    summary: "Publish a message",
    description: """
    Publishes a message to be delivered to the destination URL.

    The destination URL is specified in the `Ricqchet-Destination` header. For fan-out
    delivery to multiple destinations, use `Ricqchet-Fan-Out` with a comma-separated list
    of URLs instead. Various other `Ricqchet-*` headers control message behavior including
    delays, deduplication, retries, and batching.

    **Fan-out notes:**
    - Creates a separate message for each destination (up to 100)
    - Returns an array of message IDs
    - Cannot be combined with batching

    #{Schemas.PublishHeaders.forward_header_description()}
    """,
    parameters: Schemas.PublishHeaders.parameters(),
    request_body:
      {"Message payload", "application/json",
       %Schema{
         type: :object,
         additionalProperties: true,
         description: "The payload to deliver to the destination URL"
       }, required: false},
    responses: Schemas.Helpers.create_responses(Schemas.PublishResponse),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Publishes a message to be delivered to the destination URL.

  The destination URL is specified in the `Ricqchet-Destination` header.
  For fan-out to multiple destinations, use the `Ricqchet-Fan-Out` header.
  Various Ricqchet-* headers control message behavior:

  - `Ricqchet-Destination`: Full destination URL (required, unless using fan-out)
  - `Ricqchet-Fan-Out`: Comma-separated list of destination URLs for fan-out
  - `Ricqchet-Delay`: Delay before first attempt (e.g., "30s", "5m", "2h", "1d")
  - `Ricqchet-Dedup-Key`: Deduplication key
  - `Ricqchet-Dedup-TTL`: Dedup window in seconds (default: 300)
  - `Ricqchet-Retries`: Override max retries
  - `Ricqchet-Forward-*`: Headers to forward to destination (prefix stripped)
  - `Ricqchet-Batch-Key`: Group messages into a batch (opt-in batching)
  - `Ricqchet-Batch-Size`: Max messages per batch (default: 10)
  - `Ricqchet-Batch-Timeout`: Seconds before batch is sent (default: 5)
  """
  def create(conn, _params) do
    tenant = conn.assigns.current_tenant
    application = conn.assigns.current_application

    case get_destinations(conn) do
      {:ok, :single, destination_url} ->
        case get_batch_key(conn) do
          nil ->
            create_individual_message(conn, tenant, application, destination_url)

          batch_key ->
            create_batched_message(conn, tenant, application, destination_url, batch_key)
        end

      {:ok, :fan_out, destination_urls} ->
        # Fan-out is incompatible with batching
        case get_batch_key(conn) do
          nil ->
            create_fan_out_messages(conn, tenant, application, destination_urls)

          _batch_key ->
            {:error, :validation, "Ricqchet-Fan-Out cannot be used with Ricqchet-Batch-Key"}
        end

      {:error, reason} ->
        {:error, :validation, reason}
    end
  end

  defp get_destinations(conn) do
    single = get_req_header(conn, "ricqchet-destination")
    fan_out = get_req_header(conn, "ricqchet-fan-out")

    case {single, fan_out} do
      {[_url | _], [_urls | _]} ->
        {:error, "Cannot use both Ricqchet-Destination and Ricqchet-Fan-Out headers"}

      {[url | _], []} ->
        case Ricqchet.UrlValidator.validate_url(url) do
          :ok -> {:ok, :single, url}
          {:error, reason} -> {:error, "destination_url: #{reason}"}
        end

      {[], [urls | _]} ->
        parse_fan_out_urls(urls)

      {[], []} ->
        {:error, "Ricqchet-Destination or Ricqchet-Fan-Out header is required"}
    end
  end

  defp parse_fan_out_urls(urls_string) do
    urls =
      urls_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    cond do
      urls == [] ->
        {:error, "Ricqchet-Fan-Out header cannot be empty"}

      length(urls) > @max_fan_out_destinations ->
        {:error, "Ricqchet-Fan-Out exceeds maximum of #{@max_fan_out_destinations} destinations"}

      true ->
        validate_fan_out_urls(urls, [])
    end
  end

  defp validate_fan_out_urls([], validated), do: {:ok, :fan_out, Enum.reverse(validated)}

  defp validate_fan_out_urls([url | rest], validated) do
    case Ricqchet.UrlValidator.validate_url(url) do
      :ok -> validate_fan_out_urls(rest, [url | validated])
      {:error, reason} -> {:error, "Invalid fan-out URL '#{url}': #{reason}"}
    end
  end

  defp create_individual_message(conn, tenant, application, destination_url) do
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
        case Messages.create(tenant, attrs, application) do
          {:ok, message} ->
            conn
            |> put_status(:accepted)
            |> render(:created, message: message)

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp create_fan_out_messages(conn, tenant, application, destination_urls) do
    # Build base attributes (same for all destinations)
    base_attrs =
      %{}
      |> put_payload(conn)
      |> put_content_type(conn)
      |> put_delay(conn)
      |> put_max_retries(conn)
      |> put_forwarded_headers(conn)

    # Note: dedup is intentionally not used with fan-out since each destination
    # should be treated as a separate message

    # Create a message for each destination
    results =
      Enum.map(destination_urls, fn url ->
        attrs = Map.put(base_attrs, :destination_url, url)
        Messages.create(tenant, attrs, application)
      end)

    # Check if all succeeded
    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {successes, []} ->
        messages = Enum.map(successes, fn {:ok, msg} -> msg end)

        conn
        |> put_status(:accepted)
        |> render(:fan_out_created, messages: messages)

      {_successes, [{:error, changeset} | _]} ->
        # If any failed, return the first error
        # In a production system, you might want to handle partial failures differently
        {:error, changeset}
    end
  end

  defp create_batched_message(conn, tenant, application, destination_url, batch_key) do
    message_attrs =
      %{destination_url: destination_url}
      |> put_payload(conn)
      |> put_content_type(conn)
      |> put_forwarded_headers(conn)

    batch_opts = %{
      max_size: get_batch_size(conn),
      timeout_seconds: get_batch_timeout(conn),
      headers: Map.get(message_attrs, :headers, %{})
    }

    case BatchCollector.add_message(
           tenant,
           batch_key,
           destination_url,
           message_attrs,
           batch_opts,
           application
         ) do
      {:ok, message} ->
        conn
        |> put_status(:accepted)
        |> render(:created, message: message)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp get_batch_key(conn) do
    case get_req_header(conn, "ricqchet-batch-key") do
      [key | _] -> key
      [] -> nil
    end
  end

  # Maximum batch size to prevent memory issues
  @max_batch_size 1000
  # Maximum batch timeout (1 hour)
  @max_batch_timeout 3600

  defp get_batch_size(conn) do
    size =
      case get_req_header(conn, "ricqchet-batch-size") do
        [size | _] -> parse_integer(size, 10)
        [] -> 10
      end

    # Clamp to valid range: 1 to @max_batch_size
    size
    |> max(1)
    |> min(@max_batch_size)
  end

  defp get_batch_timeout(conn) do
    timeout =
      case get_req_header(conn, "ricqchet-batch-timeout") do
        [timeout | _] -> parse_integer(timeout, 5)
        [] -> 5
      end

    # Clamp to valid range: 1 to @max_batch_timeout
    timeout
    |> max(1)
    |> min(@max_batch_timeout)
  end

  defp put_payload(attrs, conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} ->
        case Plug.Conn.read_body(conn) do
          {:ok, body, _conn} ->
            Map.put(attrs, :payload, body)

          {:more, _partial, _conn} ->
            # Body too large (shouldn't happen with endpoint limit)
            Map.put(attrs, :payload, nil)

          {:error, _reason} ->
            Map.put(attrs, :payload, nil)
        end

      body when is_map(body) ->
        case Jason.encode(body) do
          {:ok, encoded} -> Map.put(attrs, :payload, encoded)
          {:error, _} -> Map.put(attrs, :payload, nil)
        end
    end
  end

  defp put_content_type(attrs, conn) do
    case get_req_header(conn, "content-type") do
      [content_type | _] -> Map.put(attrs, :content_type, content_type)
      [] -> attrs
    end
  end

  defp put_delay(attrs, conn) do
    case get_req_header(conn, "ricqchet-delay") do
      [delay | _] -> Map.put(attrs, :delay, parse_delay(delay))
      [] -> attrs
    end
  end

  defp put_dedup(attrs, conn) do
    attrs =
      case get_req_header(conn, "ricqchet-dedup-key") do
        [key | _] -> Map.put(attrs, :dedup_key, key)
        [] -> attrs
      end

    case get_req_header(conn, "ricqchet-dedup-ttl") do
      [ttl | _] -> Map.put(attrs, :dedup_ttl, parse_integer(ttl, 300))
      [] -> attrs
    end
  end

  defp put_max_retries(attrs, conn) do
    case get_req_header(conn, "ricqchet-retries") do
      [retries | _] -> Map.put(attrs, :max_retries, parse_integer(retries, 3))
      [] -> attrs
    end
  end

  defp put_forwarded_headers(attrs, conn) do
    forwarded =
      conn.req_headers
      |> Enum.filter(fn {key, _} -> String.starts_with?(key, "ricqchet-forward-") end)
      |> Enum.map(fn {key, value} ->
        # Strip "ricqchet-forward-" prefix
        header_name = String.replace_prefix(key, "ricqchet-forward-", "")
        # Sanitize header values to prevent header injection
        sanitized_value = sanitize_header_value(value)
        {header_name, sanitized_value}
      end)
      |> Enum.reject(fn {name, _} -> blocked_header?(name) end)
      |> Map.new()

    if map_size(forwarded) > 0 do
      Map.put(attrs, :headers, forwarded)
    else
      attrs
    end
  end

  # Sanitize header values to prevent header injection attacks
  # Removes newlines and other control characters that could be used to inject headers
  defp sanitize_header_value(value) do
    value
    |> String.replace(~r/[\r\n\x00-\x1f]/, "")
    |> String.trim()
  end

  # Block security-sensitive headers that shouldn't be forwarded
  @blocked_headers ~w(
    host
    content-length
    transfer-encoding
    connection
    keep-alive
    proxy-authenticate
    proxy-authorization
    te
    trailer
    upgrade
  )
  defp blocked_header?(name), do: String.downcase(name) in @blocked_headers

  defp check_dedup(tenant, %{dedup_key: dedup_key}) when is_binary(dedup_key) do
    case Messages.get_by_dedup_key(tenant, dedup_key) do
      nil -> :ok
      existing -> {:duplicate, existing.id}
    end
  end

  defp check_dedup(_, _), do: :ok

  # Maximum delay: 7 days in seconds
  @max_delay_seconds 7 * 24 * 60 * 60

  # Parse delay string like "30s", "5m", "2h", "1d" to seconds
  # Caps delay at 7 days to prevent unreasonable scheduling
  defp parse_delay(delay) do
    delay
    |> parse_delay_value()
    |> max(0)
    |> min(@max_delay_seconds)
  end

  defp parse_delay_value(delay) do
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
