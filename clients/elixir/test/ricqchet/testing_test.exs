defmodule Ricqchet.TestingTest do
  use ExUnit.Case, async: true

  import Ricqchet.Testing

  # Helper to simulate what the test adapter does
  defp send_publish(destination, payload, opts \\ []) do
    send(self(), {:ricqchet, {:publish, destination, payload, opts}})
  end

  defp send_fan_out(destinations, payload, opts \\ []) do
    send(self(), {:ricqchet, {:publish_fan_out, destinations, payload, opts}})
  end

  defp send_get_message(message_id) do
    send(self(), {:ricqchet, {:get_message, message_id}})
  end

  defp send_cancel_message(message_id) do
    send(self(), {:ricqchet, {:cancel_message, message_id}})
  end

  describe "assert_published/1" do
    test "passes when message was published" do
      send_publish("https://example.com", %{event: "test"})

      result = assert_published()
      assert result.destination == "https://example.com"
      assert result.payload == %{event: "test"}
    end

    test "passes when destination matches" do
      send_publish("https://example.com", %{event: "test"})

      assert_published(destination: "https://example.com")
    end

    test "passes when payload matches" do
      send_publish("https://example.com", %{event: "test"})

      assert_published(payload: %{event: "test"})
    end

    test "passes when delay option matches" do
      send_publish("https://example.com", %{event: "test"}, delay: "5m")

      assert_published(delay: "5m")
    end

    test "passes when dedup_key matches" do
      send_publish("https://example.com", %{}, dedup_key: "order-123")

      assert_published(dedup_key: "order-123")
    end

    test "passes when multiple criteria match" do
      send_publish("https://example.com", %{event: "test"}, delay: "1h")

      assert_published(
        destination: "https://example.com",
        payload: %{event: "test"},
        delay: "1h"
      )
    end

    test "fails when no message was published" do
      assert_raise ExUnit.AssertionError, ~r/Expected a publish call/, fn ->
        assert_published(timeout: 10)
      end
    end

    test "fails when destination doesn't match" do
      send_publish("https://example.com", %{event: "test"})

      assert_raise ExUnit.AssertionError, fn ->
        assert_published(destination: "https://other.com")
      end
    end
  end

  describe "refute_published/1" do
    test "passes when no message was published" do
      refute_published(timeout: 10)
    end

    test "fails when message was published" do
      send_publish("https://example.com", %{event: "test"})

      assert_raise ExUnit.AssertionError, ~r/Expected no publish/, fn ->
        refute_published(timeout: 10)
      end
    end
  end

  describe "assert_fan_out/2" do
    test "passes when destinations match" do
      destinations = ["https://a.example.com", "https://b.example.com"]
      send_fan_out(destinations, %{event: "broadcast"})

      result = assert_fan_out(destinations)
      assert MapSet.new(result.destinations) == MapSet.new(destinations)
    end

    test "passes when destinations match in different order" do
      send_fan_out(["https://a.com", "https://b.com"], %{event: "test"})

      assert_fan_out(["https://b.com", "https://a.com"])
    end

    test "passes when payload matches" do
      destinations = ["https://a.example.com"]
      send_fan_out(destinations, %{event: "broadcast"})

      assert_fan_out(destinations, payload: %{event: "broadcast"})
    end

    test "fails when destinations don't match" do
      send_fan_out(["https://a.com"], %{})

      assert_raise ExUnit.AssertionError, ~r/Expected fan-out/, fn ->
        assert_fan_out(["https://b.com"], timeout: 10)
      end
    end

    test "fails when no fan_out was called" do
      assert_raise ExUnit.AssertionError, ~r/Expected a fan-out publish/, fn ->
        assert_fan_out(["https://a.com"], timeout: 10)
      end
    end
  end

  describe "assert_get_message/2" do
    test "passes when message_id matches" do
      send_get_message("msg-123")

      assert_get_message("msg-123")
    end

    test "fails when message_id doesn't match" do
      send_get_message("msg-123")

      assert_raise ExUnit.AssertionError, fn ->
        assert_get_message("msg-456", timeout: 10)
      end
    end
  end

  describe "assert_cancel_message/2" do
    test "passes when message_id matches" do
      send_cancel_message("msg-123")

      assert_cancel_message("msg-123")
    end

    test "fails when message_id doesn't match" do
      send_cancel_message("msg-123")

      assert_raise ExUnit.AssertionError, fn ->
        assert_cancel_message("msg-456", timeout: 10)
      end
    end
  end

  describe "stub_response/3" do
    test "stubs publish response" do
      stub_response(:publish, {:error, :rate_limited})

      assert Process.get({:ricqchet_stub, :publish, :any}) == {:error, :rate_limited}
    end

    test "stubs publish for specific destination" do
      stub_response(:publish, {:error, :timeout}, destination: "https://slow.com")

      assert Process.get({:ricqchet_stub, :publish, "https://slow.com"}) == {:error, :timeout}
    end

    test "stubs get_message response" do
      stub_response(:get_message, {:error, :not_found})

      assert Process.get({:ricqchet_stub, :get_message, :any}) == {:error, :not_found}
    end

    test "stubs cancel_message response" do
      stub_response(:cancel_message, {:error, :already_dispatched})

      assert Process.get({:ricqchet_stub, :cancel_message, :any}) == {:error, :already_dispatched}
    end
  end

  describe "reset_ricqchet/0" do
    test "clears recorded calls" do
      Process.put(:ricqchet_calls, [{:publish, "dest", %{}, []}])

      reset_ricqchet()

      assert Process.get(:ricqchet_calls) == nil
    end

    test "clears stubs" do
      stub_response(:publish, {:error, :rate_limited})
      stub_response(:get_message, {:error, :not_found})

      reset_ricqchet()

      assert Process.get({:ricqchet_stub, :publish, :any}) == nil
      assert Process.get({:ricqchet_stub, :get_message, :any}) == nil
    end
  end

  describe "get_ricqchet_calls/0" do
    test "returns empty list when no calls" do
      reset_ricqchet()

      assert get_ricqchet_calls() == []
    end

    test "returns calls in order" do
      Process.put(:ricqchet_calls, [
        {:publish, "https://b.com", %{}, []},
        {:publish, "https://a.com", %{}, []}
      ])

      calls = get_ricqchet_calls()

      assert [
               {:publish, "https://a.com", %{}, []},
               {:publish, "https://b.com", %{}, []}
             ] = calls
    end
  end
end
