defmodule RicqchetWeb.Schemas.Tenant.InviteUserResponse do
  @moduledoc """
  Schema for invite user response.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "InviteUserResponse",
    description: "Response after successfully creating an invitation",
    type: :object,
    required: [:id, :email, :role, :status, :expires_at, :inserted_at],
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Invitation ID"},
      email: %Schema{type: :string, format: :email, description: "Invited email address"},
      role: %Schema{
        type: :string,
        description: "Role that will be assigned upon acceptance",
        enum: ["admin", "member", "viewer"]
      },
      status: %Schema{
        type: :string,
        description: "Invitation status",
        enum: ["pending", "accepted", "expired", "revoked"]
      },
      expires_at: %Schema{
        type: :string,
        format: "date-time",
        description: "Invitation expiration timestamp"
      },
      inserted_at: %Schema{
        type: :string,
        format: "date-time",
        description: "Invitation creation timestamp"
      }
    },
    example: %{
      "id" => "550e8400-e29b-41d4-a716-446655440000",
      "email" => "newuser@example.com",
      "role" => "member",
      "status" => "pending",
      "expires_at" => "2024-01-22T10:00:00Z",
      "inserted_at" => "2024-01-15T10:00:00Z"
    }
  })
end
