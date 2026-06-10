defmodule RicqchetWeb.Schemas.Tenant.UserResponse do
  @moduledoc """
  Schema for tenant user response.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "TenantUserResponse",
    description: "User information within a tenant",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "User ID"},
      email: %Schema{type: :string, format: :email, description: "Email address"},
      role: %Schema{
        type: :string,
        description: "User role within the tenant",
        enum: ["admin", "member", "viewer"]
      },
      status: %Schema{
        type: :string,
        description: "Account status",
        enum: ["active", "pending", "suspended"]
      },
      confirmed_at: %Schema{
        type: :string,
        format: "date-time",
        description: "Email confirmation timestamp",
        nullable: true
      },
      last_login_at: %Schema{
        type: :string,
        format: "date-time",
        description: "Last login timestamp",
        nullable: true
      },
      inserted_at: %Schema{
        type: :string,
        format: "date-time",
        description: "Account creation timestamp"
      },
      updated_at: %Schema{
        type: :string,
        format: "date-time",
        description: "Last update timestamp"
      }
    },
    required: [:id, :email, :role, :status, :inserted_at, :updated_at],
    example: %{
      "id" => "550e8400-e29b-41d4-a716-446655440000",
      "email" => "user@example.com",
      "role" => "member",
      "status" => "active",
      "confirmed_at" => "2024-01-15T10:00:00Z",
      "last_login_at" => "2024-01-20T14:00:00Z",
      "inserted_at" => "2024-01-10T08:00:00Z",
      "updated_at" => "2024-01-20T14:00:00Z"
    }
  })
end
