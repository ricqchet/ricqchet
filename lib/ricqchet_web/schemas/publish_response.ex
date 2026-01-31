defmodule RicqchetWeb.Schemas.PublishResponse do
  @moduledoc """
  Schema for publish endpoint response.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "PublishResponse",
    description: "Response when a message is accepted for delivery",
    type: :object,
    required: [:message_id],
    properties: %{
      message_id: %Schema{
        type: :string,
        format: :uuid,
        description: "Unique identifier for the queued message"
      }
    },
    example: %{message_id: "550e8400-e29b-41d4-a716-446655440000"}
  })
end
