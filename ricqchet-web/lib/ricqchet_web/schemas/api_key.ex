defmodule RicqchetWeb.Schemas.ApiKey do
  @moduledoc """
  Schema for API key resource (without sensitive data).
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ApiKey",
    description: "An API key for authenticating with the Ricqchet API (secrets redacted)",
    type: :object,
    required: [:id, :name, :prefix, :status, :scope, :created_at],
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
      prefix: %Schema{
        type: :string,
        description: "First 8 characters of the API key for identification"
      },
      status: %Schema{
        type: :string,
        enum: ["active", "revoked"],
        description: "Current status of the key"
      },
      scope: %Schema{
        type: :string,
        enum: ["relay", "subscribe"],
        description:
          "Permission scope. `relay` (default) is the full server-side key; " <>
            "`subscribe` is a browser-safe key usable only on the channels WebSocket."
      },
      last_used_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "Timestamp when the key was last used"
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
      prefix: "rq_live_",
      status: "active",
      scope: "relay",
      last_used_at: "2026-01-31T15:30:00Z",
      expires_at: nil,
      created_at: "2026-01-15T10:00:00Z"
    }
  })
end
