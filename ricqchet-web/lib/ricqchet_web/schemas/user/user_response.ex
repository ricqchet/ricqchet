defmodule RicqchetWeb.Schemas.User.UserResponse do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "UserResponse",
    description: "User profile information",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "User ID"},
      email: %Schema{type: :string, format: :email, description: "Email address"},
      name: %Schema{type: :string, description: "Display name", nullable: true},
      role: %Schema{type: :string, description: "User role", enum: ["admin", "member"]},
      status: %Schema{
        type: :string,
        description: "Account status",
        enum: ["active", "pending", "suspended"]
      },
      tenant_id: %Schema{type: :string, format: :uuid, description: "Tenant ID"},
      tenant_name: %Schema{type: :string, description: "Tenant name"},
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
    required: [:id, :email, :role, :status, :tenant_id, :tenant_name, :inserted_at, :updated_at],
    example: %{
      "id" => "123e4567-e89b-12d3-a456-426614174000",
      "email" => "user@example.com",
      "name" => "John Doe",
      "role" => "admin",
      "status" => "active",
      "tenant_id" => "123e4567-e89b-12d3-a456-426614174001",
      "tenant_name" => "Acme Corp",
      "confirmed_at" => "2024-01-15T10:30:00Z",
      "last_login_at" => "2024-01-20T14:00:00Z",
      "inserted_at" => "2024-01-10T08:00:00Z",
      "updated_at" => "2024-01-20T14:00:00Z"
    }
  })
end
