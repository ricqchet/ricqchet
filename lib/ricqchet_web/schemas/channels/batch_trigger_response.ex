defmodule RicqchetWeb.Schemas.Channels.BatchTriggerResponse do
  @moduledoc """
  Schema for the response after batch triggering channel events.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "BatchTriggerResponse",
    description: "Response after batch triggering events with per-event results",
    type: :object,
    required: [:results],
    properties: %{
      results: %Schema{
        type: :array,
        description: "Results for each event in the batch, in the same order as the request",
        items: %Schema{
          type: :object,
          required: [:channel, :event, :status],
          properties: %{
            channel: %Schema{
              type: :string,
              description: "Channel the event was targeted to"
            },
            event: %Schema{
              type: :string,
              description: "Event name that was triggered"
            },
            event_id: %Schema{
              type: :string,
              nullable: true,
              description: "Unique event ID if the event was successfully triggered"
            },
            error: %Schema{
              type: :string,
              nullable: true,
              description: "Error message if the event failed to trigger"
            },
            status: %Schema{
              type: :string,
              enum: ["ok", "error"],
              description: "Whether the event was successfully triggered"
            }
          }
        }
      }
    },
    example: %{
      results: [
        %{
          channel: "public-chat",
          event: "message:new",
          event_id: "evt_01H1X2Y3Z4",
          status: "ok"
        },
        %{
          channel: "private-updates",
          event: "status:changed",
          error: "channel not found",
          status: "error"
        }
      ]
    }
  })
end
