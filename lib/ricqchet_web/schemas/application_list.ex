defmodule RicqchetWeb.Schemas.ApplicationList do
  @moduledoc """
  Schema for paginated list of applications.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ApplicationList",
    description: "Paginated list of applications",
    type: :object,
    required: [:data, :meta],
    properties: %{
      data: %Schema{
        type: :array,
        items: Schemas.Application,
        description: "List of applications"
      },
      meta: %Schema{
        type: :object,
        required: [:total],
        properties: %{
          total: %Schema{
            type: :integer,
            minimum: 0,
            description: "Total number of applications"
          }
        },
        description: "Pagination metadata"
      }
    },
    example: %{
      data: [
        %{
          id: "550e8400-e29b-41d4-a716-446655440000",
          name: "My Production App",
          description: "Main production application",
          status: "active",
          dlq_destination_url: "https://example.com/dlq",
          api_key_count: 2,
          created_at: "2026-01-15T10:00:00Z",
          updated_at: "2026-01-20T14:30:00Z"
        }
      ],
      meta: %{
        total: 1
      }
    }
  })
end
