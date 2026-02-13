defmodule RicqchetWeb.ChannelEventController do
  @moduledoc """
  Controller for channel event history.

  Provides an endpoint for querying persisted channel events,
  supporting both "since" and "recent" query modes.
  """

  use RicqchetWeb, :controller

  alias Ricqchet.Channels
  alias Ricqchet.Channels.History

  action_fallback RicqchetWeb.FallbackController

  @doc """
  Lists events for a channel.

  ## Query modes

  With `since_id`: returns events after the given event ID.

      GET /v1/channels/:channel_name/events?since_id=<event_id>

  Without `since_id`: returns the most recent events.

      GET /v1/channels/:channel_name/events?limit=50

  ## Parameters

  - `since_id` - Event ID to fetch events after (optional)
  - `limit` - Maximum number of events to return (default: 100, max: 100)
  """
  def index(conn, %{"channel_name" => channel_name} = params) do
    application = conn.assigns.current_application

    with :ok <- check_channels_enabled(application),
         :ok <- validate_channel(channel_name),
         {:ok, events} <- fetch_events(application.id, channel_name, params) do
      render(conn, :index, events: events)
    end
  end

  defp fetch_events(application_id, channel_name, %{"since_id" => since_id} = params) do
    case History.get_events_since(application_id, channel_name, since_id, build_opts(params)) do
      {:ok, events} ->
        {:ok, events}

      {:error, :event_not_found} ->
        {:error, :validation, "event not found: may have been pruned from history"}
    end
  end

  defp fetch_events(application_id, channel_name, params) do
    {:ok, History.get_recent_events(application_id, channel_name, build_opts(params))}
  end

  defp check_channels_enabled(application) do
    if application.channels_enabled do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp validate_channel(channel_name) do
    case Channels.validate_channel_name(channel_name) do
      :ok -> :ok
      {:error, reason} -> {:error, :validation, reason}
    end
  end

  defp build_opts(params) do
    case params do
      %{"limit" => limit} when is_binary(limit) ->
        case Integer.parse(limit) do
          {n, ""} when n > 0 -> [limit: n]
          _ -> []
        end

      _ ->
        []
    end
  end
end
