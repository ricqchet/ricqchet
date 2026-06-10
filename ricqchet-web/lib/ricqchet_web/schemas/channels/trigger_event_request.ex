defmodule RicqchetWeb.Schemas.Channels.TriggerEventRequest do
  @moduledoc """
  Schema for triggering an event on one or more channels.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "TriggerEventRequest",
    description:
      "Request body for triggering an event. Specify either `channel` for a single channel or `channels` for multiple channels.",
    type: :object,
    required: [:event],
    properties: %{
      channel: %Schema{
        type: :string,
        description: "Channel name to publish the event to. Mutually exclusive with `channels`.",
        example: "public-chat"
      },
      channels: %Schema{
        type: :array,
        items: %Schema{type: :string},
        maxItems: 100,
        description:
          "List of channel names to publish the event to. Mutually exclusive with `channel`.",
        example: ["public-chat", "public-notifications"]
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
        description:
          "Socket ID of the sender to exclude from receiving the event. Used to prevent echo."
      }
    },
    example: %{
      channel: "public-chat",
      event: "message:new",
      data: %{text: "Hello, world!", user: "alice"},
      socket_id: "123.456"
    }
  })
end
