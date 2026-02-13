defmodule RicqchetWeb.ChannelMembersController do
  @moduledoc """
  Controller for channel members (presence).

  Provides an endpoint for listing connected members of a presence channel.
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ricqchet.Channels
  alias RicqchetWeb.Channels.Presence
  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  tags(["channels"])

  operation(:index,
    summary: "List channel members",
    description:
      "Returns the list of connected users for a presence channel. Only available for channels with the `presence-` prefix.",
    parameters: [
      channel_name: [
        in: :path,
        schema: %Schema{type: :string},
        required: true,
        description: "Presence channel name (must start with `presence-`)"
      ]
    ],
    responses:
      Schemas.Helpers.list_responses(
        Schemas.Channels.MemberList,
        [401, 403, 422, 429]
      ),
    security: [%{"bearer_auth" => []}]
  )

  def index(conn, %{"channel_name" => channel_name}) do
    application = conn.assigns.current_application

    with :ok <- check_channels_enabled(application),
         :ok <- validate_channel(channel_name),
         :ok <- check_presence_channel(channel_name) do
      topic = "channels:app:#{application.id}:#{channel_name}"
      presence_list = Presence.list(topic)
      render(conn, :index, members: format_members(presence_list))
    end
  end

  defp check_channels_enabled(application) do
    if application.channels_enabled,
      do: :ok,
      else: {:error, :forbidden}
  end

  defp validate_channel(channel_name) do
    case Channels.validate_channel_name(channel_name) do
      :ok -> :ok
      {:error, reason} -> {:error, :validation, reason}
    end
  end

  defp check_presence_channel("presence-" <> _), do: :ok

  defp check_presence_channel(_) do
    {:error, :validation, "members are only available for presence channels"}
  end

  defp format_members(presence_map) do
    Enum.map(presence_map, fn {user_id, %{metas: metas}} ->
      meta = List.first(metas, %{})

      %{
        user_id: user_id,
        user_info: Map.get(meta, :user_info, %{}),
        joined_at: Map.get(meta, :joined_at)
      }
    end)
  end
end
