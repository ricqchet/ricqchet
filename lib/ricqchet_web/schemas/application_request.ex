defmodule RicqchetWeb.Schemas.ApplicationRequest do
  @moduledoc """
  Schema for create application request.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ApplicationRequest",
    description: "Request body for creating a new application",
    type: :object,
    required: [:name],
    properties: %{
      name: %Schema{
        type: :string,
        minLength: 1,
        maxLength: 255,
        description: "Human-readable name for the application"
      },
      description: %Schema{
        type: :string,
        maxLength: 255,
        nullable: true,
        description: "Optional description of the application"
      },
      dlq_destination_url: %Schema{
        type: :string,
        format: :uri,
        nullable: true,
        description: "Dead letter queue destination URL (must be HTTPS)"
      }
    },
    example: %{
      name: "My Production App",
      description: "Main production application for webhooks"
    }
  })
end
