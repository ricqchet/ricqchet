defmodule RicqchetWeb.Schemas.Tenant.InviteUserRequest do
  @moduledoc """
  Schema for invite user request.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "InviteUserRequest",
    description: "Parameters for inviting a user to the tenant",
    type: :object,
    required: [:email, :role],
    properties: %{
      email: %Schema{
        type: :string,
        format: :email,
        description: "Email address to invite"
      },
      role: %Schema{
        type: :string,
        description: "Role to assign to the invited user",
        enum: ["admin", "member", "viewer"]
      }
    },
    example: %{
      "email" => "newuser@example.com",
      "role" => "member"
    }
  })
end
