defmodule RicqchetWeb.Schemas.Channels.TriggerEventResponse do
  @moduledoc """
  Schema for the response after triggering a channel event.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "TriggerEventResponse",
    description: "Response after successfully triggering an event on one or more channels",
    type: :object,
    required: [:event_ids],
    properties: %{
      event_ids: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "List of unique event IDs generated for each channel"
      },
      channel: %Schema{
        type: :string,
        description: "Channel name the event was sent to (single channel mode)"
      },
      channels: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "List of channel names the event was sent to (multi-channel mode)"
      }
    },
    example: %{
      event_ids: ["evt_01H1X2Y3Z4", "evt_01H1X2Y3Z5"],
      channels: ["public-chat", "public-notifications"]
    }
  })
end
