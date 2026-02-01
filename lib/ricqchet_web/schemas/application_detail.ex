defmodule RicqchetWeb.Schemas.ApplicationDetail do
  @moduledoc """
  Schema for detailed application resource with API keys list.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ApplicationDetail",
    description: "Detailed application information including API keys",
    type: :object,
    required: [:id, :name, :status, :api_keys, :created_at],
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
      api_keys: %Schema{
        type: :array,
        items: Schemas.ApiKey,
        description: "List of API keys (secrets redacted)"
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
      api_keys: [
        %{
          id: "660e8400-e29b-41d4-a716-446655440001",
          name: "Production Key",
          prefix: "rq_live_",
          status: "active",
          last_used_at: "2026-01-31T15:30:00Z",
          expires_at: nil,
          created_at: "2026-01-15T10:00:00Z"
        }
      ],
      created_at: "2026-01-15T10:00:00Z",
      updated_at: "2026-01-20T14:30:00Z"
    }
  })
end
