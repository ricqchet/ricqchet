defmodule RicqchetWeb.Schemas.Channels.ChannelEventHistory do
  @moduledoc """
  Schema for channel event history response.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ChannelEventHistory",
    description: "Historical events for a channel, ordered by sequence number",
    type: :object,
    required: [:events],
    properties: %{
      events: %Schema{
        type: :array,
        description: "List of historical events on the channel",
        items: %Schema{
          type: :object,
          required: [:id, :channel, :event, :sequence, :inserted_at],
          properties: %{
            id: %Schema{
              type: :string,
              description: "Unique event identifier"
            },
            channel: %Schema{
              type: :string,
              description: "Channel the event was published to"
            },
            event: %Schema{
              type: :string,
              description: "Event name"
            },
            data: %Schema{
              type: :object,
              nullable: true,
              description: "Event payload data",
              additionalProperties: true
            },
            sequence: %Schema{
              type: :integer,
              minimum: 0,
              description: "Monotonically increasing sequence number within the channel"
            },
            inserted_at: %Schema{
              type: :string,
              format: :"date-time",
              description: "Timestamp when the event was recorded"
            }
          }
        }
      }
    },
    example: %{
      events: [
        %{
          id: "evt_01H1X2Y3Z4",
          channel: "public-chat",
          event: "message:new",
          data: %{text: "Hello!", user: "alice"},
          sequence: 42,
          inserted_at: "2026-01-15T10:00:00Z"
        },
        %{
          id: "evt_01H1X2Y3Z5",
          channel: "public-chat",
          event: "message:new",
          data: %{text: "Hi there!", user: "bob"},
          sequence: 43,
          inserted_at: "2026-01-15T10:00:05Z"
        }
      ]
    }
  })
end
