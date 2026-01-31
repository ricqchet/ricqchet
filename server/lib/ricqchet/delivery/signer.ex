defmodule Ricqchet.Delivery.Signer do
  @moduledoc """
  HMAC signature generation for delivery verification.

  Signs outbound payloads with the tenant's signing secret so recipients
  can verify the request originated from Ricqchet.

  ## Signature Format

  The signature header follows this format:

      X-Ricqchet-Signature: t=<timestamp>,v1=<signature>

  Where:
  - `t` is the Unix timestamp (seconds) when the signature was generated
  - `v1` is the HMAC-SHA256 signature of `<timestamp>.<payload>`

  ## Verification

  To verify a signature:
  1. Extract `t` and `v1` from the header
  2. Compute `HMAC-SHA256(signing_secret, "<t>.<raw_body>")`
  3. Compare the computed signature with `v1` (constant-time comparison)
  4. Optionally reject if timestamp is too old (e.g., > 5 minutes)
  """

  @doc """
  Signs a payload using HMAC-SHA256.

  Returns a signature string in the format `t=<timestamp>,v1=<signature>`.

  ## Examples

      iex> Signer.sign("payload", <<1, 2, 3, ...>>)
      "t=1706745600,v1=abc123..."

  """
  @spec sign(binary(), binary(), integer() | nil) :: String.t()
  def sign(payload, signing_secret, timestamp \\ nil) do
    timestamp = timestamp || System.system_time(:second)
    signed_payload = "#{timestamp}.#{payload}"

    signature =
      :crypto.mac(:hmac, :sha256, signing_secret, signed_payload)

    "t=#{timestamp},v1=#{Base.encode16(signature, case: :lower)}"
  end

  @doc """
  Verifies a signature against a payload.

  Returns `{:ok, timestamp}` if the signature is valid, or `{:error, reason}` otherwise.

  ## Options

  - `:max_age` - Maximum age of the signature in seconds (default: 300 = 5 minutes).
    Set to `nil` to disable timestamp checking.

  ## Examples

      iex> Signer.verify("t=123,v1=abc", "payload", secret, max_age: 300)
      {:ok, 123}

      iex> Signer.verify("t=123,v1=wrong", "payload", secret)
      {:error, :invalid_signature}

  """
  @spec verify(String.t(), binary(), binary(), keyword()) ::
          {:ok, integer()} | {:error, :invalid_signature | :signature_expired | :invalid_format}
  def verify(signature_header, payload, signing_secret, opts \\ []) do
    max_age = Keyword.get(opts, :max_age, 300)

    with {:ok, timestamp, signature} <- parse_signature(signature_header),
         :ok <- verify_timestamp(timestamp, max_age),
         :ok <- verify_signature(payload, signing_secret, timestamp, signature) do
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

  defp verify_signature(payload, signing_secret, timestamp, provided_signature) do
    signed_payload = "#{timestamp}.#{payload}"

    expected_signature =
      signed_payload
      |> then(&:crypto.mac(:hmac, :sha256, signing_secret, &1))
      |> Base.encode16(case: :lower)

    if secure_compare(expected_signature, provided_signature) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  # Constant-time string comparison to prevent timing attacks
  defp secure_compare(a, b) when byte_size(a) != byte_size(b), do: false

  defp secure_compare(a, b) do
    a_bytes = :binary.bin_to_list(a)
    b_bytes = :binary.bin_to_list(b)

    a_bytes
    |> Enum.zip(b_bytes)
    |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)
    |> Kernel.==(0)
  end
end
