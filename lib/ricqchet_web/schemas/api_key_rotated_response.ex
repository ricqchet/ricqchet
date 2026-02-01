defmodule RicqchetWeb.Schemas.ApiKeyRotatedResponse do
  @moduledoc """
  Schema for API key rotation response.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ApiKeyRotatedResponse",
    description: """
    Response when an API key is rotated.

    The old key is immediately revoked and a new key is created.
    **Important:** The `new_api_key.api_key` field contains the full API key and is only shown once.
    """,
    type: :object,
    required: [:old_api_key, :new_api_key],
    properties: %{
      old_api_key: %Schema{
        type: :object,
        required: [:id, :name, :prefix, :status],
        properties: %{
          id: %Schema{
            type: :string,
            format: :uuid,
            description: "ID of the revoked key"
          },
          name: %Schema{
            type: :string,
            description: "Name of the revoked key"
          },
          prefix: %Schema{
            type: :string,
            description: "Prefix of the revoked key"
          },
          status: %Schema{
            type: :string,
            enum: ["revoked"],
            description: "Status of the old key (always 'revoked')"
          }
        },
        description: "Information about the revoked key"
      },
      new_api_key: %Schema{
        type: :object,
        required: [:id, :name, :api_key, :prefix, :status, :created_at],
        properties: %{
          id: %Schema{
            type: :string,
            format: :uuid,
            description: "ID of the new key"
          },
          name: %Schema{
            type: :string,
            description: "Name of the new key (inherited from old key)"
          },
          api_key: %Schema{
            type: :string,
            description: "The full new API key (shown only once)"
          },
          prefix: %Schema{
            type: :string,
            description: "Prefix of the new key"
          },
          status: %Schema{
            type: :string,
            enum: ["active"],
            description: "Status of the new key"
          },
          expires_at: %Schema{
            type: :string,
            format: :"date-time",
            nullable: true,
            description: "Expiration timestamp"
          },
          created_at: %Schema{
            type: :string,
            format: :"date-time",
            description: "Creation timestamp"
          }
        },
        description: "Information about the new key including the full API key"
      }
    },
    example: %{
      old_api_key: %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        name: "Production Key",
        prefix: "rq_live_a",
        status: "revoked"
      },
      new_api_key: %{
        id: "660e8400-e29b-41d4-a716-446655440001",
        name: "Production Key",
        api_key: "rq_live_xyz789abc012def345ghi678jkl901mno234pqr567",
        prefix: "rq_live_x",
        status: "active",
        expires_at: nil,
        created_at: "2026-01-31T15:30:00Z"
      }
    }
  })
end
