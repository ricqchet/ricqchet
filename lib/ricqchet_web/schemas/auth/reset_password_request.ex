defmodule RicqchetWeb.Schemas.Auth.ResetPasswordRequest do
  @moduledoc false

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ResetPasswordRequest",
    description: "Request body for completing password reset",
    type: :object,
    required: [:token, :password],
    properties: %{
      token: %Schema{
        type: :string,
        description: "The password reset token sent to the user's email"
      },
      password: %Schema{
        type: :string,
        minLength: 12,
        maxLength: 72,
        description: "New password (12-72 characters)"
      }
    },
    example: %{
      "token" => "abc123resettoken",
      "password" => "new_secure_password_123"
    }
  })
end
