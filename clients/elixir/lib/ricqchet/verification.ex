defmodule Ricqchet.Verification do
  @moduledoc """
  HMAC signature verification for Ricqchet webhook deliveries.

  ## Usage with Module Configuration

      defmodule MyApp.RicqchetWebhook do
        use Ricqchet.Verification,
          signing_secret: {:system, "RICQCHET_SIGNING_SECRET"}
      end

      # In your controller
      case MyApp.RicqchetWebhook.verify(conn) do
        {:ok, %{message_id: id, attempt: n}} -> handle_delivery(conn)
        {:error, reason} -> send_resp(conn, 401, "Invalid signature")
      end

  ## Standalone Usage

      Ricqchet.Verification.verify(conn, signing_secret)

  ## Options

  - `:signing_secret` (required) - The signing secret (string or `{:system, "ENV_VAR"}`)
  - `:max_age` (optional) - Maximum signature age in seconds (default: 300)
  """

  @signature_header "x-ricqchet-signature"
  @message_id_header "x-ricqchet-message-id"
  @batch_id_header "x-ricqchet-batch-id"
  @attempt_header "x-ricqchet-attempt"

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @signing_secret opts[:signing_secret] ||
                        raise(ArgumentError, "signing_secret is required")
      @max_age opts[:max_age] || 300

      @doc """
      Verifies the signature of a Ricqchet delivery.

      Returns `{:ok, metadata}` or `{:error, reason}`.
      """
      def verify(conn) do
        signing_secret = Ricqchet.Config.resolve(@signing_secret)
        Ricqchet.Verification.verify(conn, signing_secret, max_age: @max_age)
      end

      @doc """
      Returns the verification configuration.
      """
      def config do
        %{
          signing_secret: Ricqchet.Config.resolve(@signing_secret),
          max_age: @max_age
        }
      end
    end
  end

  @doc """
  Verifies a webhook delivery signature.

  ## Arguments

  - `conn` - A Plug.Conn struct with the request
  - `signing_secret` - The binary signing secret

  ## Options

  - `:max_age` - Maximum age of signature in seconds (default: 300)

  ## Returns

  - `{:ok, metadata}` - Valid signature with metadata (message_id, batch_id, attempt)
  - `{:error, :missing_signature}` - No signature header present
  - `{:error, :invalid_format}` - Signature header format is invalid
  - `{:error, :invalid_signature}` - Signature doesn't match
  - `{:error, :signature_expired}` - Signature timestamp too old
  """
  @spec verify(Plug.Conn.t(), binary(), keyword()) ::
          {:ok, map()} | {:error, atom()}
  def verify(conn, signing_secret, opts \\ []) do
    max_age = Keyword.get(opts, :max_age, 300)

    with {:ok, signature_header} <- get_signature_header(conn),
         {:ok, raw_body} <- get_raw_body(conn),
         {:ok, _timestamp} <-
           verify_signature(signature_header, raw_body, signing_secret, max_age) do
      {:ok, extract_metadata(conn)}
    end
  end

  @doc """
  Verifies a signature against raw payload data.

  This is useful when you have the raw request body and headers
  but not a full Plug.Conn struct.

  ## Arguments

  - `signature_header` - The X-Ricqchet-Signature header value
  - `payload` - The raw request body
  - `signing_secret` - The binary signing secret
  - `opts` - Options (same as `verify/3`)
  """
  @spec verify_payload(String.t(), binary(), binary(), keyword()) ::
          {:ok, integer()} | {:error, atom()}
  def verify_payload(signature_header, payload, signing_secret, opts \\ []) do
    max_age = Keyword.get(opts, :max_age, 300)
    verify_signature(signature_header, payload, signing_secret, max_age)
  end

  # Private functions

  defp get_signature_header(conn) do
    case Plug.Conn.get_req_header(conn, @signature_header) do
      [signature] -> {:ok, signature}
      [] -> {:error, :missing_signature}
      _ -> {:error, :invalid_format}
    end
  end

  defp get_raw_body(conn) do
    case conn.assigns[:raw_body] do
      nil ->
        # Try to read the body if not already cached
        case Plug.Conn.read_body(conn) do
          {:ok, body, _conn} -> {:ok, body}
          {:more, _body, _conn} -> {:error, :body_too_large}
          {:error, _reason} -> {:error, :body_read_error}
        end

      raw_body ->
        {:ok, raw_body}
    end
  end

  defp verify_signature(signature_header, payload, signing_secret, max_age) do
    with {:ok, timestamp, signature} <- parse_signature(signature_header),
         :ok <- verify_timestamp(timestamp, max_age),
         :ok <- verify_hmac(payload, signing_secret, timestamp, signature) do
      {:ok, timestamp}
    end
  end

  defp parse_signature(header) do
    case Regex.run(~r/^t=(\d+),v1=([a-f0-9]+)$/i, header) do
      [_, timestamp_str, signature] ->
        {:ok, String.to_integer(timestamp_str), signature}

      _ ->
        {:error, :invalid_format}
    end
  end

  defp verify_timestamp(_timestamp, nil), do: :ok

  defp verify_timestamp(timestamp, max_age) do
    now = System.system_time(:second)

    if now - timestamp <= max_age do
      :ok
    else
      {:error, :signature_expired}
    end
  end

  defp verify_hmac(payload, signing_secret, timestamp, provided_signature) do
    signed_payload = "#{timestamp}.#{payload}"

    expected_signature =
      :crypto.mac(:hmac, :sha256, signing_secret, signed_payload)
      |> Base.encode16(case: :lower)

    if secure_compare(expected_signature, String.downcase(provided_signature)) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  # Constant-time comparison to prevent timing attacks
  defp secure_compare(a, b) when byte_size(a) != byte_size(b), do: false

  defp secure_compare(a, b) do
    a_bytes = :binary.bin_to_list(a)
    b_bytes = :binary.bin_to_list(b)

    a_bytes
    |> Enum.zip(b_bytes)
    |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)
    |> Kernel.==(0)
  end

  defp extract_metadata(conn) do
    %{
      message_id: get_header_value(conn, @message_id_header),
      batch_id: get_header_value(conn, @batch_id_header),
      attempt: get_header_value(conn, @attempt_header) |> parse_attempt()
    }
  end

  defp get_header_value(conn, header) do
    case Plug.Conn.get_req_header(conn, header) do
      [value] -> value
      _ -> nil
    end
  end

  defp parse_attempt(nil), do: nil
  defp parse_attempt(str), do: String.to_integer(str)
end
