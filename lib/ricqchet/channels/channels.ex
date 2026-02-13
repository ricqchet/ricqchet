defmodule Ricqchet.Channels do
  @moduledoc """
  Context module for channel operations.

  Provides the public API for publishing events, listing active channels,
  and querying channel information.
  """

  alias Ricqchet.Channels.EventPublisher
  alias Ricqchet.Channels.SubscriberTracker

  @doc """
  Publishes an event to a channel.

  ## Options

  - `:socket_id` - Socket ID to exclude from broadcast (sender exclusion)
  """
  def publish_event(application_id, channel, event_name, data, opts \\ []) do
    EventPublisher.publish(application_id, channel, event_name, data, opts)
  end

  @doc """
  Lists all active channels for an application.

  Returns a list of maps with channel name, subscriber count, and type.
  """
  def list_channels(application_id) do
    application_id
    |> SubscriberTracker.list_active()
    |> Enum.map(fn {name, count} ->
      %{name: name, subscriber_count: count, type: channel_type(name)}
    end)
  end

  @doc """
  Gets info for a specific channel.

  Returns a map with channel name, subscriber count, type, and occupied flag.
  """
  def get_channel_info(application_id, channel_name) do
    count = SubscriberTracker.get_count(application_id, channel_name)

    %{
      name: channel_name,
      subscriber_count: count,
      type: channel_type(channel_name),
      occupied: count > 0
    }
  end

  defp channel_type("private-" <> _), do: "private"
  defp channel_type("presence-" <> _), do: "presence"
  defp channel_type(_), do: "public"
end
