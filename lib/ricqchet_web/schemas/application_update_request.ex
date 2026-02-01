defmodule RicqchetWeb.Schemas.ApplicationUpdateRequest do
  @moduledoc """
  Schema for update application request.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ApplicationUpdateRequest",
    description: "Request body for updating an application",
    type: :object,
    properties: %{
      name: %Schema{
        type: :string,
        minLength: 1,
        maxLength: 255,
        description: "Human-readable name for the application"
      },
      description: %Schema{
        type: :string,
        maxLength: 1000,
        nullable: true,
        description: "Optional description of the application"
      },
      status: %Schema{
        type: :string,
        enum: ["active", "suspended"],
        description: "Application status"
      },
      dlq_destination_url: %Schema{
        type: :string,
        format: :uri,
        nullable: true,
        description: "Dead letter queue destination URL (must be HTTPS)"
      }
    },
    example: %{
      name: "Updated App Name",
      status: "active"
    }
  })
end
