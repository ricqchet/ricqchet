defmodule Ricqchet.Adapters.Test do
  @moduledoc """
  Test adapter for Ricqchet that captures calls and supports stubbing.

  This adapter is designed for testing code that uses Ricqchet clients.
  It captures all calls and sends them as messages to the test process,
  allowing you to make assertions about what was published.

  ## Setup

  Configure the adapter in `config/test.exs`:

      config :ricqchet, adapter: Ricqchet.Adapters.Test

  ## Usage

  Use with `Ricqchet.Testing` for a clean assertion API:

      import Ricqchet.Testing

      test "publishes order event" do
        {:ok, _} = MyApp.Queue.publish(%{event: "order.created"})

        assert_published destination: "https://example.com",
                         payload: %{event: "order.created"}
      end

  ## Stubbing Responses

  You can stub responses using `Ricqchet.Testing.stub_response/2`:

      stub_response(:publish, {:error, %Ricqchet.Error{type: :rate_limited}})

      assert {:error, %{type: :rate_limited}} = MyApp.Queue.publish(%{})

  ## Async Tests

  This adapter supports async tests by using the `$callers` process dictionary
  to find the test process. Each test process receives only the messages from
  its own calls.

  ## Global Mode

  For integration tests that spawn processes, use `Ricqchet.Testing.set_ricqchet_global/1`
  to set a shared test process. Note: tests using global mode should use `async: false`.
  """

  @behaviour Ricqchet.Client.Adapter

  @impl true
  def publish(_config, destination, payload, opts) do
    call = {:publish, destination, payload, opts}
    record_call(call)
    notify_test_process({:ricqchet, call})

    case get_stub_response(:publish, destination) do
      nil -> {:ok, %{message_id: generate_message_id()}}
      response -> response
    end
  end

  @impl true
  def publish_fan_out(_config, destinations, payload, opts) do
    call = {:publish_fan_out, destinations, payload, opts}
    record_call(call)
    notify_test_process({:ricqchet, call})

    case get_stub_response(:publish_fan_out, destinations) do
      nil ->
        message_ids = Enum.map(destinations, fn _ -> generate_message_id() end)
        {:ok, %{message_ids: message_ids}}

      response ->
        response
    end
  end

  @impl true
  def get_message(_config, message_id) do
    call = {:get_message, message_id}
    record_call(call)
    notify_test_process({:ricqchet, call})

    case get_stub_response(:get_message, message_id) do
      nil ->
        {:ok,
         %{
           "id" => message_id,
           "status" => "delivered",
           "attempts" => 1,
           "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
         }}

      response ->
        response
    end
  end

  @impl true
  def cancel_message(_config, message_id) do
    call = {:cancel_message, message_id}
    record_call(call)
    notify_test_process({:ricqchet, call})

    case get_stub_response(:cancel_message, message_id) do
      nil -> {:ok, %{"cancelled" => true}}
      response -> response
    end
  end

  @impl true
  def get_signing_secret(_config) do
    call = {:get_signing_secret}
    record_call(call)
    notify_test_process({:ricqchet, call})

    case get_stub_response(:get_signing_secret, nil) do
      nil -> {:ok, :crypto.strong_rand_bytes(32)}
      response -> response
    end
  end

  # Internal helpers

  defp record_call(call) do
    calls = Process.get(:ricqchet_calls, [])
    Process.put(:ricqchet_calls, [call | calls])
  end

  defp notify_test_process(message) do
    for pid <- callers(), do: send(pid, message)
  end

  defp callers do
    case Application.get_env(:ricqchet, :shared_test_process) do
      nil ->
        # In async tests, use $callers to find the test process
        Enum.uniq([self() | List.wrap(Process.get(:"$callers"))])

      pid ->
        # In global mode, use the configured process
        [pid]
    end
  end

  defp get_stub_response(operation, key) do
    # First check for a specific stub, then fall back to a wildcard stub
    Process.get({:ricqchet_stub, operation, key}) ||
      Process.get({:ricqchet_stub, operation, :any})
  end

  defp generate_message_id do
    # Generate a UUID-like message ID for testing
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    |> IO.iodata_to_binary()
  end
end
