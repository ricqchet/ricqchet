defmodule Ricqchet.Adapters.TestTest do
  use ExUnit.Case, async: true

  alias Ricqchet.Adapters.Test, as: TestAdapter

  describe "publish/4" do
    test "returns success with generated message_id" do
      config = %{base_url: "http://test", api_key: "key", timeout: 5000}

      assert {:ok, %{message_id: id}} =
               TestAdapter.publish(config, "https://example.com", %{event: "test"}, [])

      assert is_binary(id)
      assert String.length(id) > 0
    end

    test "sends message to calling process" do
      config = %{base_url: "http://test", api_key: "key", timeout: 5000}
      payload = %{event: "test"}

      TestAdapter.publish(config, "https://example.com", payload, delay: "5m")

      assert_receive {:ricqchet, {:publish, "https://example.com", ^payload, opts}}
      assert opts[:delay] == "5m"
    end

    test "returns stubbed response when set" do
      config = %{base_url: "http://test", api_key: "key", timeout: 5000}
      Process.put({:ricqchet_stub, :publish, :any}, {:error, :rate_limited})

      assert {:error, :rate_limited} =
               TestAdapter.publish(config, "https://example.com", %{}, [])
    end
  end

  describe "publish_fan_out/4" do
    test "returns success with generated message_ids" do
      config = %{base_url: "http://test", api_key: "key", timeout: 5000}
      destinations = ["https://a.example.com", "https://b.example.com"]

      assert {:ok, %{message_ids: ids}} =
               TestAdapter.publish_fan_out(config, destinations, %{event: "test"}, [])

      assert length(ids) == 2
      assert Enum.all?(ids, &is_binary/1)
    end

    test "sends message to calling process" do
      config = %{base_url: "http://test", api_key: "key", timeout: 5000}
      destinations = ["https://a.example.com", "https://b.example.com"]

      TestAdapter.publish_fan_out(config, destinations, %{event: "broadcast"}, [])

      assert_receive {:ricqchet, {:publish_fan_out, ^destinations, %{event: "broadcast"}, _opts}}
    end
  end

  describe "get_message/2" do
    test "returns default message response" do
      config = %{base_url: "http://test", api_key: "key", timeout: 5000}

      assert {:ok, message} = TestAdapter.get_message(config, "msg-123")
      assert message["id"] == "msg-123"
      assert message["status"] == "delivered"
    end

    test "sends message to calling process" do
      config = %{base_url: "http://test", api_key: "key", timeout: 5000}

      TestAdapter.get_message(config, "msg-123")

      assert_receive {:ricqchet, {:get_message, "msg-123"}}
    end

    test "returns stubbed response when set" do
      config = %{base_url: "http://test", api_key: "key", timeout: 5000}
      Process.put({:ricqchet_stub, :get_message, :any}, {:error, :not_found})

      assert {:error, :not_found} = TestAdapter.get_message(config, "nonexistent")
    end
  end

  describe "cancel_message/2" do
    test "returns success response" do
      config = %{base_url: "http://test", api_key: "key", timeout: 5000}

      assert {:ok, %{"cancelled" => true}} = TestAdapter.cancel_message(config, "msg-123")
    end

    test "sends message to calling process" do
      config = %{base_url: "http://test", api_key: "key", timeout: 5000}

      TestAdapter.cancel_message(config, "msg-123")

      assert_receive {:ricqchet, {:cancel_message, "msg-123"}}
    end
  end

  describe "get_signing_secret/1" do
    test "returns a 32-byte secret" do
      config = %{base_url: "http://test", api_key: "key", timeout: 5000}

      assert {:ok, secret} = TestAdapter.get_signing_secret(config)
      assert byte_size(secret) == 32
    end

    test "sends message to calling process" do
      config = %{base_url: "http://test", api_key: "key", timeout: 5000}

      TestAdapter.get_signing_secret(config)

      assert_receive {:ricqchet, {:get_signing_secret}}
    end
  end
end
