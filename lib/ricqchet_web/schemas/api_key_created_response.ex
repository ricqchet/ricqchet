defmodule RicqchetWeb.Schemas.ApiKeyCreatedResponse do
  @moduledoc """
  Schema for API key creation response.

  This is the only time the full API key is returned.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ApiKeyCreatedResponse",
    description: """
    Response when an API key is created.

    **Important:** The `api_key` field contains the full API key and is only shown once.
    Store it securely - it cannot be retrieved again.
    """,
    type: :object,
    required: [:id, :name, :api_key, :prefix, :status, :created_at],
    properties: %{
      id: %Schema{
        type: :string,
        format: :uuid,
        description: "Unique API key identifier"
      },
      name: %Schema{
        type: :string,
        description: "Human-readable name for the key"
      },
      api_key: %Schema{
        type: :string,
        description: "The full API key (shown only once)"
      },
      prefix: %Schema{
        type: :string,
        description: "First 8 characters of the API key for identification"
      },
      status: %Schema{
        type: :string,
        enum: ["active"],
        description: "Status of the key (always 'active' on creation)"
      },
      expires_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "Expiration timestamp (null for non-expiring keys)"
      },
      created_at: %Schema{
        type: :string,
        format: :"date-time",
        description: "Timestamp when the key was created"
      }
    },
    example: %{
      id: "550e8400-e29b-41d4-a716-446655440000",
      name: "Production Key",
      api_key: "rq_live_abc123def456ghi789jkl012mno345pqr678stu901",
      prefix: "rq_live_",
      status: "active",
      expires_at: nil,
      created_at: "2026-01-15T10:00:00Z"
    }
  })
end
