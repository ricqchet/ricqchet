defmodule RicqchetWeb.Schemas.Auth.LoginRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "LoginRequest",
    description: "Request body for user login",
    type: :object,
    properties: %{
      email: %Schema{
        type: :string,
        format: :email,
        description: "User's email address"
      },
      password: %Schema{
        type: :string,
        description: "User's password",
        minLength: 8
      }
    },
    required: [:email, :password],
    example: %{
      "email" => "user@example.com",
      "password" => "secure_password_123"
    }
  })
end
