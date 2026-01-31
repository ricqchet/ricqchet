defmodule RicqchetWeb.Schemas.ErrorResponse do
  @moduledoc """
  Schema for API error responses.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ErrorResponse",
    description: "API error response",
    type: :object,
    required: [:error, :message],
    properties: %{
      error: %Schema{
        type: :string,
        description: "Error code identifier",
        example: "not_found"
      },
      message: %Schema{
        type: :string,
        description: "Human-readable error message",
        example: "Resource not found"
      }
    },
    example: %{
      error: "not_found",
      message: "Resource not found"
    }
  })
end
