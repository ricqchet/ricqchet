defmodule RicqchetWeb.Schemas.Auth.ChangePasswordRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ChangePasswordRequest",
    description: "Request body for changing password",
    type: :object,
    properties: %{
      current_password: %Schema{
        type: :string,
        description: "The user's current password"
      },
      new_password: %Schema{
        type: :string,
        description: "The new password (minimum 12 characters)",
        minLength: 12
      }
    },
    required: [:current_password, :new_password],
    example: %{
      "current_password" => "old_password_123",
      "new_password" => "new_secure_password_456"
    }
  })
end
