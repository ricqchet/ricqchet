defmodule Ricqchet.Client do
  @moduledoc """
  Macro for defining Ricqchet client modules with baked-in configuration.

  ## Usage

      defmodule MyApp.Queue do
        use Ricqchet.Client,
          base_url: "https://your-ricqchet.fly.dev",
          api_key: {:system, "RICQCHET_API_KEY"},
          destination: "https://myapp.com/webhook"
      end

  ## Options

  - `:base_url` (required) - The Ricqchet server URL
  - `:api_key` (required) - API key string or `{:system, "ENV_VAR"}`
  - `:destination` (optional) - Default destination URL for messages
  - `:timeout` (optional) - HTTP timeout in milliseconds (default: 30_000)

  ## Generated Functions

  When `:destination` is configured:
  - `publish(payload, opts \\\\ [])` - Publish with default destination
  - `publish_fan_out(destinations, payload, opts \\\\ [])` - Fan-out delivery

  Always generated:
  - `publish_to(destination, payload, opts \\\\ [])` - Publish to explicit destination
  - `get_message(message_id)` - Get message status
  - `cancel_message(message_id)` - Cancel a pending message
  - `get_signing_secret()` - Retrieve the signing secret
  - `config()` - Returns the client configuration

  ## Testing

  For testing, configure the test adapter in your `config/test.exs`:

      config :ricqchet, adapter: Ricqchet.Adapters.Test

  Then use `Ricqchet.Testing` for assertions:

      import Ricqchet.Testing

      test "publishes message" do
        {:ok, _} = MyApp.Queue.publish(%{event: "test"})
        assert_published destination: "https://myapp.com/webhook"
      end

  See `Ricqchet.Testing` for more details.
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @base_url Keyword.fetch!(opts, :base_url)
      @api_key opts[:api_key] || raise(ArgumentError, "api_key is required")
      @destination opts[:destination]
      @timeout opts[:timeout] || 30_000

      @doc """
      Returns the client configuration.
      """
      def config do
        %{
          base_url: @base_url,
          api_key: Ricqchet.Config.resolve(@api_key),
          destination: @destination,
          timeout: @timeout
        }
      end

      defp adapter do
        Application.get_env(:ricqchet, :adapter, Ricqchet.Client.HTTP)
      end

      if @destination do
        @doc """
        Publishes a message to the configured default destination.

        ## Options

        - `:delay` - Delay delivery (e.g., "30s", "5m", "1h")
        - `:dedup_key` - Deduplication key
        - `:dedup_ttl` - Deduplication TTL in seconds (default: 300)
        - `:retries` - Max retry attempts (default: 3)
        - `:forward_headers` - Headers to forward to destination
        - `:content_type` - Content-Type header (default: "application/json")
        - `:destination` - Override the default destination

        ## Examples

            {:ok, %{message_id: id}} = MyQueue.publish(%{event: "created"})
            {:ok, %{message_id: id}} = MyQueue.publish(%{event: "created"}, delay: "5m")

        """
        def publish(payload, opts \\ []) do
          destination = Keyword.get(opts, :destination, @destination)
          adapter().publish(config(), destination, payload, opts)
        end
      end

      @doc """
      Publishes a message to a specific destination.

      See `publish/2` for available options.
      """
      def publish_to(destination, payload, opts \\ []) do
        adapter().publish(config(), destination, payload, opts)
      end

      @doc """
      Publishes a message to multiple destinations (fan-out).

      ## Examples

          {:ok, %{message_ids: ids}} = MyQueue.publish_fan_out(
            ["https://a.example.com", "https://b.example.com"],
            %{event: "broadcast"}
          )

      """
      def publish_fan_out(destinations, payload, opts \\ []) when is_list(destinations) do
        adapter().publish_fan_out(config(), destinations, payload, opts)
      end

      @doc """
      Gets the status and details of a message.

      ## Examples

          {:ok, message} = MyQueue.get_message("550e8400-e29b-41d4-a716-446655440000")

      """
      def get_message(message_id) do
        adapter().get_message(config(), message_id)
      end

      @doc """
      Cancels a pending message.

      Returns `{:ok, %{cancelled: true}}` on success, or
      `{:error, :already_dispatched}` if the message has already been sent.

      ## Examples

          {:ok, %{cancelled: true}} = MyQueue.cancel_message("550e8400-...")

      """
      def cancel_message(message_id) do
        adapter().cancel_message(config(), message_id)
      end

      @doc """
      Retrieves the signing secret for webhook verification.

      ## Examples

          {:ok, signing_secret} = MyQueue.get_signing_secret()

      """
      def get_signing_secret do
        adapter().get_signing_secret(config())
      end
    end
  end
end
