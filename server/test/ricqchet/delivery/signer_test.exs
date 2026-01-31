defmodule Ricqchet.Delivery.SignerTest do
  use ExUnit.Case, async: true

  alias Ricqchet.Delivery.Signer

  @signing_secret :crypto.strong_rand_bytes(32)

  describe "sign/2" do
    test "generates a signature in the correct format" do
      signature = Signer.sign("test payload", @signing_secret)

      assert signature =~ ~r/^t=\d+,v1=[a-f0-9]{64}$/
    end

    test "signature varies with different payloads" do
      sig1 = Signer.sign("payload1", @signing_secret)
      sig2 = Signer.sign("payload2", @signing_secret)

      # Extract v1 signatures
      [_, v1_1] = Regex.run(~r/v1=([a-f0-9]+)/, sig1)
      [_, v1_2] = Regex.run(~r/v1=([a-f0-9]+)/, sig2)

      refute v1_1 == v1_2
    end

    test "signature varies with different secrets" do
      secret1 = :crypto.strong_rand_bytes(32)
      secret2 = :crypto.strong_rand_bytes(32)
      timestamp = 1_706_745_600

      sig1 = Signer.sign("payload", secret1, timestamp)
      sig2 = Signer.sign("payload", secret2, timestamp)

      refute sig1 == sig2
    end

    test "uses provided timestamp when given" do
      timestamp = 1_706_745_600
      signature = Signer.sign("payload", @signing_secret, timestamp)

      assert signature =~ "t=#{timestamp},"
    end

    test "handles empty payload" do
      signature = Signer.sign("", @signing_secret)

      assert signature =~ ~r/^t=\d+,v1=[a-f0-9]{64}$/
    end
  end

  describe "verify/4" do
    test "verifies valid signature" do
      timestamp = System.system_time(:second)
      signature = Signer.sign("payload", @signing_secret, timestamp)

      assert {:ok, ^timestamp} = Signer.verify(signature, "payload", @signing_secret)
    end

    test "returns error for invalid signature" do
      timestamp = System.system_time(:second)

      signature =
        "t=#{timestamp},v1=0000000000000000000000000000000000000000000000000000000000000000"

      assert {:error, :invalid_signature} = Signer.verify(signature, "payload", @signing_secret)
    end

    test "returns error for expired signature" do
      # Create a signature from 10 minutes ago
      old_timestamp = System.system_time(:second) - 600
      signature = Signer.sign("payload", @signing_secret, old_timestamp)

      assert {:error, :signature_expired} =
               Signer.verify(signature, "payload", @signing_secret, max_age: 300)
    end

    test "allows expired signature when max_age is nil" do
      old_timestamp = System.system_time(:second) - 600
      signature = Signer.sign("payload", @signing_secret, old_timestamp)

      assert {:ok, ^old_timestamp} =
               Signer.verify(signature, "payload", @signing_secret, max_age: nil)
    end

    test "returns error for malformed signature header" do
      assert {:error, :invalid_format} =
               Signer.verify("invalid", "payload", @signing_secret)

      assert {:error, :invalid_format} =
               Signer.verify("t=abc,v1=def", "payload", @signing_secret)

      assert {:error, :invalid_format} =
               Signer.verify("", "payload", @signing_secret)
    end

    test "returns error when payload doesn't match" do
      signature = Signer.sign("original", @signing_secret)

      assert {:error, :invalid_signature} =
               Signer.verify(signature, "modified", @signing_secret)
    end

    test "returns error when secret doesn't match" do
      other_secret = :crypto.strong_rand_bytes(32)
      signature = Signer.sign("payload", @signing_secret)

      assert {:error, :invalid_signature} =
               Signer.verify(signature, "payload", other_secret)
    end
  end
end
