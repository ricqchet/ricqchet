defmodule Ricqchet.Channels.Auth do
  @moduledoc """
  Handles authorization for private and presence channels.

  When a client subscribes to a `private-` or `presence-` prefixed channel,
  this module calls the customer's auth endpoint to verify access.
  """

  require Logger

  alias Ricqchet.Channels.NamespaceConfig

  @doc """
  Authorizes a user to join a private or presence channel.

  Resolves the auth endpoint (namespace-specific first, then application-level fallback)
  and POSTs to it with the channel details. The customer's server responds with
  200 OK (authorized) or 403 Forbidden.

  Returns `{:ok, auth_data}` on success or `{:error, reason}` on failure.
  """
  @spec authorize(map(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, atom()}
  def authorize(application, channel_name, user_id, socket_id) do
    case resolve_auth_endpoint(application, channel_name) do
      {:ok, endpoint} ->
        call_auth_endpoint(endpoint, channel_name, user_id, socket_id)

      {:error, :no_auth_endpoint} = error ->
        Logger.warning("No auth endpoint configured for private channel",
          application_id: application.id,
          channel: channel_name
        )

        error
    end
  end

  defp resolve_auth_endpoint(application, channel_name) do
    case NamespaceConfig.get_namespace_for_channel(application.id, channel_name) do
      {:ok, %{auth_endpoint: endpoint}} when is_binary(endpoint) and endpoint != "" ->
        {:ok, endpoint}

      _ ->
        case application.channels_auth_endpoint do
          endpoint when is_binary(endpoint) and endpoint != "" -> {:ok, endpoint}
          _ -> {:error, :no_auth_endpoint}
        end
    end
  end

  defp call_auth_endpoint(endpoint, channel_name, user_id, socket_id) do
    body = %{
      channel: channel_name,
      user_id: user_id,
      socket_id: socket_id
    }

    case Req.post(endpoint,
           json: body,
           receive_timeout: 5_000,
           connect_options: [timeout: 3_000]
         ) do
      {:ok, %Req.Response{status: status, body: response_body}} when status in 200..299 ->
        auth_data = if is_map(response_body), do: response_body, else: %{}
        {:ok, auth_data}

      {:ok, %Req.Response{status: 403}} ->
        {:error, :forbidden}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Auth endpoint returned unexpected status",
          status: status,
          endpoint: endpoint,
          channel: channel_name
        )

        {:error, :auth_unavailable}

      {:error, reason} ->
        Logger.warning("Auth endpoint request failed",
          reason: inspect(reason),
          endpoint: endpoint,
          channel: channel_name
        )

        {:error, :auth_unavailable}
    end
  end
end
