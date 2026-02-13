defmodule RicqchetWeb.ChannelJSON do
  @moduledoc """
  JSON views for channel endpoints.
  """

  def render("created.json", %{event_ids: event_ids, channels: [channel]}) do
    %{event_ids: event_ids, channel: channel}
  end

  def render("created.json", %{event_ids: event_ids, channels: channels}) do
    %{event_ids: event_ids, channels: channels}
  end

  def render("index.json", %{channels: channels}) do
    %{channels: Enum.map(channels, &channel_summary/1)}
  end

  def render("show.json", %{channel: channel}) do
    data = %{
      name: channel.name,
      type: channel.type,
      subscriber_count: channel.subscriber_count,
      occupied: channel.occupied
    }

    case Map.get(channel, :members) do
      nil -> data
      members -> Map.put(data, :members, members)
    end
  end

  defp channel_summary(channel) do
    %{
      name: channel.name,
      subscriber_count: channel.subscriber_count,
      type: channel.type
    }
  end
end
