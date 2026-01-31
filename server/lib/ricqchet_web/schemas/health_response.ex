defmodule RicqchetWeb.Schemas.HealthResponse do
  @moduledoc """
  Schema for health check response.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "HealthResponse",
    description: "Health check response indicating service status",
    type: :object,
    required: [:status],
    properties: %{
      status: %Schema{
        type: :string,
        enum: ["ok"],
        description: "Service status",
        example: "ok"
      }
    },
    example: %{status: "ok"}
  })
end
