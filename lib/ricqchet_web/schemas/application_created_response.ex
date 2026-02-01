defmodule RicqchetWeb.Schemas.ApplicationCreatedResponse do
  @moduledoc """
  Schema for application creation response with the initial API key.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ApplicationCreatedResponse",
    description:
      "Response after creating a new application, includes the initial API key (shown once)",
    type: :object,
    required: [:id, :name, :status, :api_key, :created_at],
    properties: %{
      id: %Schema{
        type: :string,
        format: :uuid,
        description: "Unique application identifier"
      },
      name: %Schema{
        type: :string,
        description: "Human-readable name for the application"
      },
      description: %Schema{
        type: :string,
        nullable: true,
        description: "Optional description of the application"
      },
      status: %Schema{
        type: :string,
        enum: ["active", "suspended"],
        description: "Current status of the application"
      },
      dlq_destination_url: %Schema{
        type: :string,
        format: :uri,
        nullable: true,
        description: "Dead letter queue destination URL for failed messages"
      },
      api_key: %Schema{
        type: :string,
        description:
          "The initial API key for this application. Store this securely - it will not be shown again."
      },
      created_at: %Schema{
        type: :string,
        format: :"date-time",
        description: "Timestamp when the application was created"
      }
    },
    example: %{
      id: "550e8400-e29b-41d4-a716-446655440000",
      name: "My Production App",
      description: "Main production application",
      status: "active",
      dlq_destination_url: nil,
      api_key: "rq_live_abc123def456...",
      created_at: "2026-01-15T10:00:00Z"
    }
  })
end
