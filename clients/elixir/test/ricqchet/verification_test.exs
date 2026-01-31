defmodule Ricqchet.VerificationTest do
  use ExUnit.Case, async: true

  alias Ricqchet.Verification

  @signing_secret :crypto.strong_rand_bytes(32)

  defp sign(payload, signing_secret, timestamp \\ nil) do
    timestamp = timestamp || System.system_time(:second)
    signed_payload = "#{timestamp}.#{payload}"

    signature =
      :crypto.mac(:hmac, :sha256, signing_secret, signed_payload)
      |> Base.encode16(case: :lower)

    "t=#{timestamp},v1=#{signature}"
  end

  describe "verify_payload/4" do
    test "verifies valid signature" do
      payload = ~s({"event": "test"})
      timestamp = System.system_time(:second)
      signature = sign(payload, @signing_secret, timestamp)

      assert {:ok, ^timestamp} =
               Verification.verify_payload(signature, payload, @signing_secret)
    end

    test "returns error for invalid signature" do
      payload = ~s({"event": "test"})
      timestamp = System.system_time(:second)

      signature =
        "t=#{timestamp},v1=0000000000000000000000000000000000000000000000000000000000000000"

      assert {:error, :invalid_signature} =
               Verification.verify_payload(signature, payload, @signing_secret)
    end

    test "returns error for expired signature" do
      payload = ~s({"event": "test"})
      old_timestamp = System.system_time(:second) - 600
      signature = sign(payload, @signing_secret, old_timestamp)

      assert {:error, :signature_expired} =
               Verification.verify_payload(signature, payload, @signing_secret, max_age: 300)
    end

    test "allows expired signature when max_age is nil" do
      payload = ~s({"event": "test"})
      old_timestamp = System.system_time(:second) - 600
      signature = sign(payload, @signing_secret, old_timestamp)

      assert {:ok, ^old_timestamp} =
               Verification.verify_payload(signature, payload, @signing_secret, max_age: nil)
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} =
               Verification.verify_payload("invalid", "payload", @signing_secret)
    end

    test "returns error for modified payload" do
      payload = ~s({"event": "test"})
      signature = sign(payload, @signing_secret)

      assert {:error, :invalid_signature} =
               Verification.verify_payload(signature, "modified", @signing_secret)
    end

    test "returns error for wrong secret" do
      payload = ~s({"event": "test"})
      signature = sign(payload, @signing_secret)
      other_secret = :crypto.strong_rand_bytes(32)

      assert {:error, :invalid_signature} =
               Verification.verify_payload(signature, payload, other_secret)
    end
  end
end
