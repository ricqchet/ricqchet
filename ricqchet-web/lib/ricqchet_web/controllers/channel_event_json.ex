defmodule RicqchetWeb.ChannelEventJSON do
  @moduledoc """
  JSON views for channel event history endpoints.
  """

  alias Ricqchet.Channels.ChannelEvent

  def render("index.json", %{events: events}) do
    %{events: Enum.map(events, &event_data/1)}
  end

  defp event_data(%ChannelEvent{} = event) do
    %{
      id: event.id,
      channel: event.channel,
      event: event.event_name,
      data: decode_data(event.data),
      sequence: event.sequence,
      inserted_at: event.inserted_at
    }
  end

  defp decode_data(nil), do: nil

  defp decode_data(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> decoded
      _ -> data
    end
  end

  defp decode_data(data), do: data
end
