defmodule RicqchetWeb.Schemas.Application do
  @moduledoc """
  Schema for application resource.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "Application",
    description: "An application that can use the Ricqchet API",
    type: :object,
    required: [:id, :name, :status, :created_at],
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
      api_key_count: %Schema{
        type: :integer,
        minimum: 0,
        description: "Number of API keys associated with this application"
      },
      created_at: %Schema{
        type: :string,
        format: :"date-time",
        description: "Timestamp when the application was created"
      },
      updated_at: %Schema{
        type: :string,
        format: :"date-time",
        description: "Timestamp when the application was last updated"
      }
    },
    example: %{
      id: "550e8400-e29b-41d4-a716-446655440000",
      name: "My Production App",
      description: "Main production application",
      status: "active",
      dlq_destination_url: "https://example.com/dlq",
      api_key_count: 2,
      created_at: "2026-01-15T10:00:00Z",
      updated_at: "2026-01-20T14:30:00Z"
    }
  })
end
