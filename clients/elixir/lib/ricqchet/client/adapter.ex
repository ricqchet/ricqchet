defmodule Ricqchet.Client.Adapter do
  @moduledoc """
  Behaviour for Ricqchet HTTP adapters.

  This behaviour defines the contract for HTTP adapters used by `Ricqchet.Client`.
  The default implementation is `Ricqchet.Client.HTTP`, which makes real HTTP requests.

  For testing, you can use `Ricqchet.Adapters.Test` which captures calls and supports
  stubbing responses. See `Ricqchet.Testing` for assertion helpers.

  ## Custom Adapters

  You can implement your own adapter by implementing this behaviour:

      defmodule MyApp.LoggingAdapter do
        @behaviour Ricqchet.Client.Adapter

        @impl true
        def publish(config, destination, payload, opts) do
          Logger.info("Publishing to \#{destination}")
          Ricqchet.Client.HTTP.publish(config, destination, payload, opts)
        end

        # ... implement other callbacks
      end

  Then configure it in your application:

      config :ricqchet, adapter: MyApp.LoggingAdapter

  """

  @type config :: %{
          base_url: String.t(),
          api_key: String.t(),
          timeout: pos_integer(),
          destination: String.t() | nil
        }

  @type publish_response :: {:ok, %{message_id: String.t()}} | {:error, term()}
  @type fan_out_response :: {:ok, %{message_ids: [String.t()]}} | {:error, term()}
  @type message_response :: {:ok, map()} | {:error, term()}
  @type cancel_response :: {:ok, map()} | {:error, :not_found | :already_dispatched | term()}
  @type secret_response :: {:ok, binary()} | {:error, term()}

  @doc """
  Publishes a message to a destination.

  ## Parameters

    * `config` - Client configuration map
    * `destination` - Target URL for the message
    * `payload` - Message payload (binary or term to be JSON-encoded)
    * `opts` - Options like `:delay`, `:dedup_key`, `:retries`, etc.

  ## Returns

    * `{:ok, %{message_id: id}}` on success
    * `{:error, reason}` on failure

  """
  @callback publish(config(), String.t(), term(), keyword()) :: publish_response()

  @doc """
  Publishes a message to multiple destinations (fan-out).

  ## Parameters

    * `config` - Client configuration map
    * `destinations` - List of target URLs
    * `payload` - Message payload
    * `opts` - Options like `:delay`, `:dedup_key`, etc.

  ## Returns

    * `{:ok, %{message_ids: [id, ...]}}` on success
    * `{:error, reason}` on failure

  """
  @callback publish_fan_out(config(), [String.t()], term(), keyword()) :: fan_out_response()

  @doc """
  Gets the status of a message.

  ## Parameters

    * `config` - Client configuration map
    * `message_id` - The message ID to look up

  ## Returns

    * `{:ok, message}` with message details on success
    * `{:error, :not_found}` if the message doesn't exist
    * `{:error, reason}` on other failures

  """
  @callback get_message(config(), String.t()) :: message_response()

  @doc """
  Cancels a pending message.

  ## Parameters

    * `config` - Client configuration map
    * `message_id` - The message ID to cancel

  ## Returns

    * `{:ok, %{"cancelled" => true}}` on success
    * `{:error, :not_found}` if the message doesn't exist
    * `{:error, :already_dispatched}` if already sent
    * `{:error, reason}` on other failures

  """
  @callback cancel_message(config(), String.t()) :: cancel_response()

  @doc """
  Retrieves the signing secret for webhook verification.

  ## Parameters

    * `config` - Client configuration map

  ## Returns

    * `{:ok, secret}` with the binary signing secret
    * `{:error, reason}` on failure

  """
  @callback get_signing_secret(config()) :: secret_response()
end
