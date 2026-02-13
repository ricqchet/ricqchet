defmodule RicqchetWeb.ChannelUserController do
  @moduledoc """
  Controller for managing channel user connections.
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  tags(["channels"])

  operation(:delete,
    summary: "Disconnect a user",
    description:
      "Disconnects all WebSocket connections for a specific user from the application's channels.",
    parameters: [
      user_id: [
        in: :path,
        schema: %Schema{type: :string},
        required: true,
        description: "User ID to disconnect"
      ]
    ],
    responses:
      Schemas.Helpers.delete_responses(
        Schemas.Channels.DisconnectResponse,
        [401, 403, 429]
      ),
    security: [%{"bearer_auth" => []}]
  )

  def delete(conn, %{"user_id" => user_id}) do
    application = conn.assigns.current_application

    with :ok <- check_channels_enabled(application) do
      topic = "channel_socket:#{application.id}:#{user_id}"
      RicqchetWeb.Endpoint.broadcast(topic, "disconnect", %{})

      conn
      |> put_status(:ok)
      |> render(:deleted, user_id: user_id)
    end
  end

  defp check_channels_enabled(application) do
    if application.channels_enabled do
      :ok
    else
      {:error, :forbidden}
    end
  end
end
