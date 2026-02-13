defmodule RicqchetWeb.ChannelUserController do
  @moduledoc """
  Controller for managing channel user connections.
  """

  use RicqchetWeb, :controller

  action_fallback RicqchetWeb.FallbackController

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
