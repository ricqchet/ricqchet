defmodule RicqchetWeb.Schemas.Tenant.CreateUserRequest do
  @moduledoc """
  Schema for the create-user request (admin only).
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "CreateUserRequest",
    description: "Parameters for creating a user. Requires admin role.",
    type: :object,
    required: [:email, :role],
    properties: %{
      email: %Schema{
        type: :string,
        format: :email,
        description: "Email address for the new user"
      },
      role: %Schema{
        type: :string,
        description: "Role to assign to the new user",
        enum: ["admin", "member", "viewer"]
      },
      password: %Schema{
        type: :string,
        description:
          "Optional password (12-72 characters). If omitted, the server generates " <>
            "a secure password and returns it once in the response.",
        minLength: 12,
        maxLength: 72,
        nullable: true
      }
    },
    example: %{
      "email" => "newuser@example.com",
      "role" => "member"
    }
  })
end
