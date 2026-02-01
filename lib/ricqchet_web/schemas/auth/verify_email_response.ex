defmodule RicqchetWeb.Schemas.Auth.VerifyEmailResponse do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "VerifyEmailResponse",
    description: "Response after successful email verification",
    type: :object,
    properties: %{
      message: %Schema{
        type: :string,
        description: "Success message"
      },
      user: %Schema{
        type: :object,
        properties: %{
          id: %Schema{type: :string, format: :uuid},
          email: %Schema{type: :string, format: :email},
          status: %Schema{type: :string},
          confirmed_at: %Schema{type: :string, format: "date-time"}
        }
      }
    },
    required: [:message, :user],
    example: %{
      "message" => "Email verified successfully",
      "user" => %{
        "id" => "123e4567-e89b-12d3-a456-426614174000",
        "email" => "user@example.com",
        "status" => "active",
        "confirmed_at" => "2024-01-15T10:30:00Z"
      }
    }
  })
end
