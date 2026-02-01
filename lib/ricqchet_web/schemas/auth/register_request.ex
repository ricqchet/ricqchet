defmodule RicqchetWeb.Schemas.Auth.RegisterRequest do
  @moduledoc """
  Schema for user registration request.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "RegisterRequest",
    description: "Request body for user registration",
    type: :object,
    required: [:email, :password, :tenant_name],
    properties: %{
      email: %Schema{
        type: :string,
        format: :email,
        description: "User's email address"
      },
      password: %Schema{
        type: :string,
        minLength: 12,
        maxLength: 72,
        description: "User's password (12-72 characters)"
      },
      tenant_name: %Schema{
        type: :string,
        minLength: 1,
        description: "Name for the new organization/tenant"
      }
    },
    example: %{
      email: "user@example.com",
      password: "secure_password_123",
      tenant_name: "My Organization"
    }
  })
end
