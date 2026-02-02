defmodule RicqchetWeb.Schemas.Tenant.UserList do
  @moduledoc """
  Schema for paginated list of tenant users.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "TenantUserList",
    description: "Paginated list of users in a tenant",
    type: :object,
    required: [:data, :meta],
    properties: %{
      data: %Schema{
        type: :array,
        items: Schemas.Tenant.UserResponse,
        description: "List of users"
      },
      meta: %Schema{
        type: :object,
        required: [:total, :has_next_page, :has_previous_page],
        properties: %{
          total: %Schema{
            type: :integer,
            minimum: 0,
            description: "Total number of users"
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
            description: "Cursor for the first item"
          },
          end_cursor: %Schema{
            type: :string,
            nullable: true,
            description: "Cursor for the last item"
          },
          current_offset: %Schema{
            type: :integer,
            nullable: true,
            description: "Current offset (offset pagination only)"
          },
          current_page: %Schema{
            type: :integer,
            nullable: true,
            description: "Current page number (offset pagination only)"
          },
          total_pages: %Schema{
            type: :integer,
            nullable: true,
            description: "Total number of pages (offset pagination only)"
          }
        },
        description: "Pagination metadata"
      }
    },
    example: %{
      data: [
        %{
          id: "550e8400-e29b-41d4-a716-446655440000",
          email: "admin@example.com",
          role: "admin",
          status: "active",
          confirmed_at: "2024-01-15T10:00:00Z",
          last_login_at: "2024-01-20T14:00:00Z",
          inserted_at: "2024-01-10T08:00:00Z",
          updated_at: "2024-01-20T14:00:00Z"
        }
      ],
      meta: %{
        total: 5,
        has_next_page: false,
        has_previous_page: false,
        start_cursor: nil,
        end_cursor: nil
      }
    }
  })
end
