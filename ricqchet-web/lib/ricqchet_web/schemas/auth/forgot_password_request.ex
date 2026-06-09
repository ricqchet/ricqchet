defmodule RicqchetWeb.Schemas.Auth.ForgotPasswordRequest do
  @moduledoc false

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ForgotPasswordRequest",
    description: "Request body for password reset request",
    type: :object,
    required: [:email],
    properties: %{
      email: %Schema{
        type: :string,
        format: :email,
        description: "Email address of the account to reset password for"
      }
    },
    example: %{
      "email" => "user@example.com"
    }
  })
end
