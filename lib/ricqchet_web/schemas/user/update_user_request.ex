defmodule RicqchetWeb.Schemas.User.UpdateUserRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "UpdateUserRequest",
    description: "Request body for updating user profile",
    type: :object,
    properties: %{
      name: %Schema{
        type: :string,
        description: "Display name",
        maxLength: 255
      }
    },
    example: %{
      "name" => "John Doe"
    }
  })
end
