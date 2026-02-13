defmodule RicqchetWeb.Schemas.Channels.BatchTriggerRequest do
  @moduledoc """
  Schema for batch triggering events on channels.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "BatchTriggerRequest",
    description: "Request body for triggering multiple events in a single batch request",
    type: :object,
    required: [:batch],
    properties: %{
      batch: %Schema{
        type: :array,
        minItems: 1,
        maxItems: 100,
        description: "List of events to trigger",
        items: %Schema{
          type: :object,
          required: [:channel, :event],
          properties: %{
            channel: %Schema{
              type: :string,
              description: "Channel name to publish the event to"
            },
            event: %Schema{
              type: :string,
              minLength: 1,
              maxLength: 255,
              description: "Name of the event to trigger"
            },
            data: %Schema{
              type: :object,
              description: "Arbitrary JSON payload to send with the event",
              additionalProperties: true
            },
            socket_id: %Schema{
              type: :string,
              nullable: true,
              description: "Socket ID of the sender to exclude from receiving the event"
            }
          }
        }
      }
    },
    example: %{
      batch: [
        %{channel: "public-chat", event: "message:new", data: %{text: "Hello!"}},
        %{
          channel: "private-updates",
          event: "status:changed",
          data: %{status: "online"},
          socket_id: "123.456"
        }
      ]
    }
  })
end
