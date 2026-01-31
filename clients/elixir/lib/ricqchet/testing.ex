defmodule Ricqchet.Testing do
  @moduledoc """
  Test helpers for Ricqchet client modules.

  This module provides assertion functions for testing code that uses Ricqchet
  clients. It works with `Ricqchet.Adapters.Test` to capture and verify calls.

  ## Setup

  Configure the test adapter in `config/test.exs`:

      config :ricqchet, adapter: Ricqchet.Adapters.Test

  ## Usage

      defmodule MyApp.QueueTest do
        use ExUnit.Case, async: true
        import Ricqchet.Testing

        test "publishes order created event" do
          {:ok, %{message_id: id}} = MyApp.Queue.publish(%{event: "order.created", id: 123})

          assert is_binary(id)
          assert_published destination: "https://myapp.com/webhook",
                           payload: %{event: "order.created", id: 123}
        end

        test "publishes with delay" do
          MyApp.Queue.publish(%{event: "reminder"}, delay: "1h")

          assert_published delay: "1h"
        end

        test "handles rate limiting" do
          stub_response(:publish, {:error, %Ricqchet.Error{type: :rate_limited}})

          assert {:error, %{type: :rate_limited}} = MyApp.Queue.publish(%{event: "test"})
        end

        test "fan-out to multiple destinations" do
          dests = ["https://a.example.com", "https://b.example.com"]
          {:ok, _} = MyApp.Queue.publish_fan_out(dests, %{event: "broadcast"})

          assert_fan_out dests
        end
      end

  ## Async Tests

  All assertion functions work correctly with async tests. Each test process
  receives only the messages from its own calls.

  ## Global Mode

  For integration tests that spawn processes (e.g., testing GenServers),
  use `set_ricqchet_global/1`:

      test "worker publishes messages", %{worker: worker} do
        set_ricqchet_global()

        GenServer.call(worker, :do_work)

        assert_published destination: "https://example.com"
      end

  Note: Tests using global mode must use `async: false`.
  """

  import ExUnit.Assertions

  @default_timeout 100

  @doc """
  Asserts that a message was published matching the given criteria.

  ## Options

    * `:destination` - Expected destination URL
    * `:payload` - Expected payload (exact match)
    * `:delay` - Expected delay option
    * `:dedup_key` - Expected deduplication key
    * `:dedup_ttl` - Expected deduplication TTL
    * `:retries` - Expected retries option
    * `:timeout` - How long to wait for the message (default: #{@default_timeout}ms)

  ## Examples

      # Assert any publish happened
      assert_published()

      # Assert publish to specific destination
      assert_published destination: "https://example.com"

      # Assert publish with specific payload
      assert_published payload: %{event: "order.created"}

      # Assert publish with options
      assert_published delay: "5m", dedup_key: "order-123"

      # Combine multiple criteria
      assert_published destination: "https://example.com",
                       payload: %{event: "test"},
                       delay: "1h"

  ## Returns

  Returns a map with the actual call details:

      %{destination: "...", payload: %{...}, opts: [...]}

  """
  def assert_published(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    receive do
      {:ricqchet, {:publish, destination, payload, call_opts}} ->
        if expected = opts[:destination], do: assert(destination == expected)
        if expected = opts[:payload], do: assert(payload == expected)
        if expected = opts[:delay], do: assert(call_opts[:delay] == expected)
        if expected = opts[:dedup_key], do: assert(call_opts[:dedup_key] == expected)
        if expected = opts[:dedup_ttl], do: assert(call_opts[:dedup_ttl] == expected)
        if expected = opts[:retries], do: assert(call_opts[:retries] == expected)

        %{destination: destination, payload: payload, opts: call_opts}
    after
      timeout ->
        flunk("Expected a publish call but none was received within #{timeout}ms")
    end
  end

  @doc """
  Asserts that no message was published within the timeout period.

  ## Options

    * `:timeout` - How long to wait (default: #{@default_timeout}ms)

  ## Examples

      test "does not publish when validation fails" do
        MyApp.Queue.maybe_publish(invalid_data)

        refute_published()
      end

  """
  def refute_published(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    receive do
      {:ricqchet, {:publish, destination, payload, _opts}} ->
        flunk(
          "Expected no publish call, but got publish to #{inspect(destination)} " <>
            "with payload: #{inspect(payload)}"
        )
    after
      timeout -> :ok
    end
  end

  @doc """
  Asserts that a fan-out publish was called with the expected destinations.

  ## Parameters

    * `destinations` - Expected list of destination URLs (order doesn't matter)
    * `opts` - Options:
      * `:payload` - Expected payload
      * `:timeout` - How long to wait (default: #{@default_timeout}ms)

  ## Examples

      dests = ["https://a.example.com", "https://b.example.com"]
      MyApp.Queue.publish_fan_out(dests, %{event: "broadcast"})

      assert_fan_out(dests)
      assert_fan_out(dests, payload: %{event: "broadcast"})

  ## Returns

  Returns a map with the actual call details:

      %{destinations: [...], payload: %{...}, opts: [...]}

  """
  def assert_fan_out(destinations, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    receive do
      {:ricqchet, {:publish_fan_out, actual_dests, payload, call_opts}} ->
        assert MapSet.new(actual_dests) == MapSet.new(destinations),
               "Expected fan-out to #{inspect(destinations)}, got #{inspect(actual_dests)}"

        if expected = opts[:payload], do: assert(payload == expected)

        %{destinations: actual_dests, payload: payload, opts: call_opts}
    after
      timeout ->
        flunk(
          "Expected a fan-out publish to #{inspect(destinations)} " <>
            "but none was received within #{timeout}ms"
        )
    end
  end

  @doc """
  Asserts that `get_message/1` was called with the expected message ID.

  ## Examples

      MyApp.Queue.get_message("msg-123")

      assert_get_message("msg-123")

  """
  def assert_get_message(message_id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    receive do
      {:ricqchet, {:get_message, ^message_id}} ->
        :ok
    after
      timeout ->
        flunk("Expected get_message(#{inspect(message_id)}) but none was received")
    end
  end

  @doc """
  Asserts that `cancel_message/1` was called with the expected message ID.

  ## Examples

      MyApp.Queue.cancel_message("msg-123")

      assert_cancel_message("msg-123")

  """
  def assert_cancel_message(message_id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    receive do
      {:ricqchet, {:cancel_message, ^message_id}} ->
        :ok
    after
      timeout ->
        flunk("Expected cancel_message(#{inspect(message_id)}) but none was received")
    end
  end

  @doc """
  Stubs the response for a given operation.

  This allows you to control what the test adapter returns, useful for
  testing error handling.

  ## Parameters

    * `operation` - The operation to stub: `:publish`, `:publish_fan_out`,
      `:get_message`, `:cancel_message`, or `:get_signing_secret`
    * `response` - The response to return

  ## Options

    * `:destination` - Only stub for this specific destination (for `:publish`)
    * `:destinations` - Only stub for these destinations (for `:publish_fan_out`)
    * `:message_id` - Only stub for this message ID (for `:get_message`, `:cancel_message`)

  ## Examples

      # Stub all publish calls to return an error
      stub_response(:publish, {:error, %Ricqchet.Error{type: :rate_limited}})

      # Stub publish to a specific destination
      stub_response(:publish, {:error, :network_error}, destination: "https://slow.example.com")

      # Stub get_message to return not found
      stub_response(:get_message, {:error, :not_found}, message_id: "nonexistent")

      # Stub cancel_message to return already dispatched
      stub_response(:cancel_message, {:error, :already_dispatched})

  """
  def stub_response(operation, response, opts \\ [])

  def stub_response(:publish, response, opts) do
    key = Keyword.get(opts, :destination, :any)
    Process.put({:ricqchet_stub, :publish, key}, response)
  end

  def stub_response(:publish_fan_out, response, opts) do
    key = Keyword.get(opts, :destinations, :any)
    Process.put({:ricqchet_stub, :publish_fan_out, key}, response)
  end

  def stub_response(:get_message, response, opts) do
    key = Keyword.get(opts, :message_id, :any)
    Process.put({:ricqchet_stub, :get_message, key}, response)
  end

  def stub_response(:cancel_message, response, opts) do
    key = Keyword.get(opts, :message_id, :any)
    Process.put({:ricqchet_stub, :cancel_message, key}, response)
  end

  def stub_response(:get_signing_secret, response, _opts) do
    Process.put({:ricqchet_stub, :get_signing_secret, nil}, response)
  end

  @doc """
  Sets up global test mode for integration tests.

  Use this when testing code that spawns processes that use Ricqchet,
  such as GenServers or Tasks. The specified process (or the calling process
  if none specified) will receive all Ricqchet messages.

  **Important:** Tests using global mode must use `async: false`.

  ## Examples

      defmodule MyApp.WorkerTest do
        use ExUnit.Case, async: false
        import Ricqchet.Testing

        setup do
          set_ricqchet_global()
          :ok
        end

        test "worker publishes on tick" do
          {:ok, worker} = MyApp.Worker.start_link()

          send(worker, :tick)

          assert_published destination: "https://example.com"
        end
      end

  """
  def set_ricqchet_global(pid \\ self()) do
    Application.put_env(:ricqchet, :shared_test_process, pid)

    ExUnit.Callbacks.on_exit(fn ->
      Application.delete_env(:ricqchet, :shared_test_process)
    end)
  end

  @doc """
  Clears all stubs and recorded calls.

  Useful in setup blocks when you want a clean slate.

  ## Examples

      setup do
        reset_ricqchet()
        :ok
      end

  """
  def reset_ricqchet do
    Process.delete(:ricqchet_calls)

    Process.get_keys()
    |> Enum.filter(&match?({:ricqchet_stub, _, _}, &1))
    |> Enum.each(&Process.delete/1)

    :ok
  end

  @doc """
  Returns all recorded Ricqchet calls in the current process.

  Useful for debugging or making complex assertions.

  ## Examples

      MyApp.Queue.publish(%{event: "a"})
      MyApp.Queue.publish(%{event: "b"})

      calls = get_ricqchet_calls()
      assert length(calls) == 2

  """
  def get_ricqchet_calls do
    Process.get(:ricqchet_calls, []) |> Enum.reverse()
  end
end
