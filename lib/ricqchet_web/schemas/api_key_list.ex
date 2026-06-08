defmodule RicqchetWeb.Schemas.ApiKeyList do
  @moduledoc """
  Schema for paginated list of API keys.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ApiKeyList",
    description: "Paginated list of API keys",
    type: :object,
    required: [:data, :meta],
    properties: %{
      data: %Schema{
        type: :array,
        items: Schemas.ApiKey,
        description: "List of API keys (secrets redacted)"
      },
      meta: %Schema{
        type: :object,
        required: [:total],
        properties: %{
          total: %Schema{
            type: :integer,
            minimum: 0,
            description: "Total number of API keys"
          }
        },
        description: "Pagination metadata"
      }
    },
    example: %{
      data: [
        %{
          id: "550e8400-e29b-41d4-a716-446655440000",
          name: "Production Key",
          prefix: "rq_live_",
          status: "active",
          scope: "relay",
          last_used_at: "2026-01-31T15:30:00Z",
          expires_at: nil,
          created_at: "2026-01-15T10:00:00Z"
        }
      ],
      meta: %{
        total: 1
      }
    }
  })
end
