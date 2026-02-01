defmodule RicqchetWeb.Schemas.Tenant.UserRemovedResponse do
  @moduledoc """
  Schema for user removed response.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "UserRemovedResponse",
    description: "Response after successfully removing a user from the tenant",
    type: :object,
    required: [:id, :message],
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Removed user ID"},
      message: %Schema{type: :string, description: "Confirmation message"}
    },
    example: %{
      "id" => "550e8400-e29b-41d4-a716-446655440000",
      "message" => "User removed from tenant"
    }
  })
end
