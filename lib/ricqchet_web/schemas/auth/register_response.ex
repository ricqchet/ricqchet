defmodule RicqchetWeb.Schemas.Auth.RegisterResponse do
  @moduledoc """
  Schema for user registration response.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "RegisterResponse",
    description:
      "Response after successful registration. User must verify email before logging in.",
    type: :object,
    required: [:user, :message],
    properties: %{
      user: %Schema{
        type: :object,
        required: [:id, :email, :role, :status],
        properties: %{
          id: %Schema{type: :string, format: :uuid},
          email: %Schema{type: :string, format: :email},
          role: %Schema{type: :string, enum: ["admin", "member", "viewer"]},
          status: %Schema{type: :string, enum: ["pending", "active", "suspended"]},
          tenant_id: %Schema{type: :string, format: :uuid}
        }
      },
      message: %Schema{
        type: :string,
        description: "Instructions for the user"
      }
    },
    example: %{
      user: %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        email: "user@example.com",
        role: "admin",
        status: "pending",
        tenant_id: "660e8400-e29b-41d4-a716-446655440000"
      },
      message: "Registration successful. Please check your email to verify your account."
    }
  })
end
