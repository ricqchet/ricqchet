defmodule RicqchetWeb.Schemas.ApiKeyRevokedResponse do
  @moduledoc """
  Schema for API key revocation response.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ApiKeyRevokedResponse",
    description: "Response when an API key is revoked",
    type: :object,
    required: [:id, :name, :prefix, :status, :scope, :revoked, :revoked_at],
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
        enum: ["revoked"],
        description: "Status of the key (always 'revoked' after revocation)"
      },
      scope: %Schema{
        type: :string,
        enum: ["relay", "subscribe"],
        description: "Permission scope of the key (`relay` or `subscribe`)"
      },
      revoked: %Schema{
        type: :boolean,
        description: "Confirmation that the key was revoked"
      },
      revoked_at: %Schema{
        type: :string,
        format: :"date-time",
        description: "Timestamp when the key was revoked"
      }
    },
    example: %{
      id: "550e8400-e29b-41d4-a716-446655440000",
      name: "Production Key",
      prefix: "rq_live_",
      status: "revoked",
      scope: "relay",
      revoked: true,
      revoked_at: "2026-01-31T15:30:00Z"
    }
  })
end
