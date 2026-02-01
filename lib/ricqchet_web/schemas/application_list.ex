defmodule RicqchetWeb.Schemas.ApplicationList do
  @moduledoc """
  Schema for paginated list of applications.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ApplicationList",
    description: "Paginated list of applications with cursor-based pagination support",
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
        required: [:total, :has_next_page, :has_previous_page],
        properties: %{
          total: %Schema{
            type: :integer,
            minimum: 0,
            description: "Total number of applications matching the query"
          },
          has_next_page: %Schema{
            type: :boolean,
            description: "Whether there are more items after the current page"
          },
          has_previous_page: %Schema{
            type: :boolean,
            description: "Whether there are more items before the current page"
          },
          start_cursor: %Schema{
            type: :string,
            nullable: true,
            description:
              "Cursor for the first item in the current page (use with 'before' for backward pagination)"
          },
          end_cursor: %Schema{
            type: :string,
            nullable: true,
            description:
              "Cursor for the last item in the current page (use with 'after' for forward pagination)"
          },
          current_offset: %Schema{
            type: :integer,
            nullable: true,
            description: "Current offset (only present for offset-based pagination)"
          },
          current_page: %Schema{
            type: :integer,
            nullable: true,
            description: "Current page number (only present for offset-based pagination)"
          },
          total_pages: %Schema{
            type: :integer,
            nullable: true,
            description: "Total number of pages (only present for offset-based pagination)"
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
        total: 42,
        has_next_page: true,
        has_previous_page: false,
        start_cursor: nil,
        end_cursor: "g3QAAAABZAALaW5zZXJ0ZWRfYXR0AAAADQ"
      }
    }
  })
end
