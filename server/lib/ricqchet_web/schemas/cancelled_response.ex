defmodule RicqchetWeb.Schemas.CancelledResponse do
  @moduledoc """
  Schema for message cancellation response.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "CancelledResponse",
    description: "Confirmation that a message was successfully cancelled",
    type: :object,
    required: [:cancelled],
    properties: %{
      cancelled: %Schema{
        type: :boolean,
        description: "Indicates the message was cancelled",
        example: true
      }
    },
    example: %{cancelled: true}
  })
end
