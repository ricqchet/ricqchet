defmodule RicqchetWeb.Schemas.Tenant.UpdateUserRoleRequest do
  @moduledoc """
  Schema for update user role request.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "UpdateUserRoleRequest",
    description: "Parameters for updating a user's role",
    type: :object,
    required: [:role],
    properties: %{
      role: %Schema{
        type: :string,
        description: "New role for the user",
        enum: ["admin", "member", "viewer"]
      }
    },
    example: %{
      "role" => "admin"
    }
  })
end
