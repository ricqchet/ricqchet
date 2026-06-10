defmodule RicqchetWeb.Schemas.Tenant.CreateUserResponse do
  @moduledoc """
  Schema for the create-user response.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "CreateUserResponse",
    description:
      "The created user. The one-time `password` is present only when the server " <>
        "generated it — store it immediately, as it cannot be retrieved later.",
    type: :object,
    required: [:id, :email, :role, :status, :inserted_at, :updated_at],
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "User ID"},
      email: %Schema{type: :string, format: :email, description: "Email address"},
      role: %Schema{
        type: :string,
        description: "User role",
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
      },
      password: %Schema{
        type: :string,
        description:
          "One-time generated password. Present only when the server generated it; " <>
            "store it now as it cannot be retrieved later.",
        nullable: true
      }
    },
    example: %{
      "id" => "550e8400-e29b-41d4-a716-446655440000",
      "email" => "newuser@example.com",
      "role" => "member",
      "status" => "active",
      "confirmed_at" => "2024-01-15T10:00:00Z",
      "last_login_at" => nil,
      "inserted_at" => "2024-01-15T10:00:00Z",
      "updated_at" => "2024-01-15T10:00:00Z",
      "password" => "generated-one-time-password"
    }
  })
end
